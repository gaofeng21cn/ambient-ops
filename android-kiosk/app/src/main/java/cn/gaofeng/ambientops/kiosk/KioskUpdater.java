package cn.gaofeng.ambientops.kiosk;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.BatteryManager;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONException;

final class KioskUpdater {
    private static final String TAG = "AmbientOpsUpdater";
    private static final String UPDATE_PATH = "/api/v1/kiosk/update";
    private static final String EXPECTED_SIGNER_SHA256 =
        "4e5f5732645986e5a861446028846fcfb571b9dd006d87da19aa60f152639206";
    private static final int CONNECT_TIMEOUT_MS = 10_000;
    private static final int READ_TIMEOUT_MS = 30_000;
    private static final int MAX_MANIFEST_BYTES = 64 * 1024;
    private static final int MAX_APK_BYTES = 32 * 1024 * 1024;

    private final Context context;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean checking = new AtomicBoolean();

    KioskUpdater(Context context) {
        this.context = context.getApplicationContext();
        pruneCachedUpdates();
    }

    void check(String endpoint) {
        if (endpoint == null || !checking.compareAndSet(false, true)) {
            return;
        }
        executor.execute(() -> {
            try {
                if (!isChargingAndOnWifi()) {
                    return;
                }
                checkAndInstall(endpoint);
            } catch (Exception error) {
                Log.w(TAG, "Update check failed", error);
            } finally {
                checking.set(false);
            }
        });
    }

    void close() {
        executor.shutdownNow();
    }

    private void checkAndInstall(String endpoint) throws Exception {
        URL manifestUrl = new URL(new URL(endpoint), UPDATE_PATH);
        String body = readText(manifestUrl);
        if (body == null) {
            return;
        }
        UpdateMetadata update = UpdateMetadata.parse(body);
        PackageInfo installed = packageInfo(context.getPackageName(), false);
        if (!update.isNewerThan(installed.getLongVersionCode())) {
            return;
        }
        String installedSigner = signerSha256(installed);
        if (
            !EXPECTED_SIGNER_SHA256.equals(installedSigner)
                || !EXPECTED_SIGNER_SHA256.equals(update.signerSha256)
        ) {
            throw new SecurityException("Installed app or update manifest signer is not trusted");
        }

        URL apkUrl = new URL(manifestUrl, update.apkPath);
        File apk = download(apkUrl, update.versionCode);
        try {
            if (!update.sha256.equals(sha256(apk))) {
                throw new SecurityException("Downloaded APK SHA-256 does not match the manifest");
            }
            PackageInfo candidate = packageInfo(apk.getAbsolutePath(), true);
            if (!context.getPackageName().equals(candidate.packageName)) {
                throw new SecurityException("Downloaded APK package name is not trusted");
            }
            if (
                candidate.getLongVersionCode() != update.versionCode
                    || !update.versionName.equals(candidate.versionName)
            ) {
                throw new SecurityException("Downloaded APK version does not match the manifest");
            }
            if (!EXPECTED_SIGNER_SHA256.equals(signerSha256(candidate))) {
                throw new SecurityException("Downloaded APK signer is not trusted");
            }
            installWithRoot(apk);
        } finally {
            if (apk.exists() && !apk.delete()) {
                Log.w(TAG, "Could not remove cached update " + apk.getName());
            }
        }
    }

    private String readText(URL url) throws IOException {
        HttpURLConnection connection = open(url);
        try {
            int status = connection.getResponseCode();
            if (status == HttpURLConnection.HTTP_NOT_FOUND) {
                return null;
            }
            if (status != HttpURLConnection.HTTP_OK) {
                throw new IOException("Update manifest returned HTTP " + status);
            }
            return new String(
                readLimited(connection.getInputStream(), MAX_MANIFEST_BYTES),
                StandardCharsets.UTF_8
            );
        } finally {
            connection.disconnect();
        }
    }

    private File download(URL url, long versionCode) throws IOException {
        HttpURLConnection connection = open(url);
        File target = new File(context.getCacheDir(), "kiosk-update-" + versionCode + ".apk");
        File temporary = new File(target.getAbsolutePath() + ".part");
        if (temporary.exists() && !temporary.delete()) {
            throw new IOException("Could not replace partial update");
        }
        try {
            int status = connection.getResponseCode();
            if (status != HttpURLConnection.HTTP_OK) {
                throw new IOException("Update APK returned HTTP " + status);
            }
            int contentLength = connection.getContentLength();
            if (contentLength <= 0 || contentLength > MAX_APK_BYTES) {
                throw new IOException("Update APK length is invalid");
            }
            byte[] buffer = new byte[16 * 1024];
            int total = 0;
            try (
                InputStream input = connection.getInputStream();
                FileOutputStream output = new FileOutputStream(temporary)
            ) {
                int count;
                while ((count = input.read(buffer)) != -1) {
                    total += count;
                    if (total > MAX_APK_BYTES) {
                        throw new IOException("Update APK is too large");
                    }
                    output.write(buffer, 0, count);
                }
                output.getFD().sync();
            }
            if (total != contentLength) {
                throw new IOException("Update APK download was incomplete");
            }
            if (target.exists() && !target.delete()) {
                throw new IOException("Could not replace cached update");
            }
            if (!temporary.renameTo(target)) {
                throw new IOException("Could not finalize cached update");
            }
            return target;
        } finally {
            connection.disconnect();
            if (temporary.exists() && !temporary.delete()) {
                Log.w(TAG, "Could not remove partial update");
            }
        }
    }

    private HttpURLConnection open(URL url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(READ_TIMEOUT_MS);
        connection.setUseCaches(false);
        connection.setRequestProperty("Accept", "application/json, application/vnd.android.package-archive");
        connection.setRequestProperty("User-Agent", "AmbientOpsKiosk");
        return connection;
    }

    private PackageInfo packageInfo(String value, boolean archive)
        throws PackageManager.NameNotFoundException {
        PackageManager packages = context.getPackageManager();
        int flags = PackageManager.GET_SIGNING_CERTIFICATES;
        PackageInfo info = archive
            ? packages.getPackageArchiveInfo(value, flags)
            : packages.getPackageInfo(value, flags);
        if (info == null || info.signingInfo == null) {
            throw new PackageManager.NameNotFoundException("Package signing information is missing");
        }
        return info;
    }

    private String signerSha256(PackageInfo info) throws Exception {
        Signature[] signers = info.signingInfo.getApkContentsSigners();
        if (signers == null || signers.length != 1) {
            throw new SecurityException("Exactly one APK signer is required");
        }
        return sha256(signers[0].toByteArray());
    }

    private void installWithRoot(File apk) throws Exception {
        String command = "pm install -r " + shellQuote(apk.getAbsolutePath());
        Process process = new ProcessBuilder("su", "-c", command)
            .redirectErrorStream(true)
            .start();
        String output;
        try (InputStream input = process.getInputStream()) {
            output = new String(readLimited(input, 8 * 1024), StandardCharsets.UTF_8);
        }
        int status = process.waitFor();
        if (status != 0 || !output.contains("Success")) {
            throw new IOException(
                "Root package install failed with status "
                    + status
                    + ": "
                    + output.trim()
            );
        }
    }

    private boolean isChargingAndOnWifi() {
        Intent battery = context.registerReceiver(
            null,
            new IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        );
        int status = battery == null
            ? -1
            : battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
        boolean charging =
            status == BatteryManager.BATTERY_STATUS_CHARGING
                || status == BatteryManager.BATTERY_STATUS_FULL;
        ConnectivityManager connectivity =
            (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo network = connectivity == null ? null : connectivity.getActiveNetworkInfo();
        return charging
            && network != null
            && network.isConnected()
            && network.getType() == ConnectivityManager.TYPE_WIFI;
    }

    private void pruneCachedUpdates() {
        File[] files = context.getCacheDir().listFiles(
            (directory, name) -> name.startsWith("kiosk-update-")
        );
        if (files == null) {
            return;
        }
        for (File file : files) {
            if (!file.delete()) {
                Log.w(TAG, "Could not remove old cached update " + file.getName());
            }
        }
    }

    private static byte[] readLimited(InputStream input, int limit) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8 * 1024];
        int total = 0;
        int count;
        while ((count = input.read(buffer)) != -1) {
            total += count;
            if (total > limit) {
                throw new IOException("Response exceeds its size limit");
            }
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static String sha256(File file) throws Exception {
        try (InputStream input = new java.io.FileInputStream(file)) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[16 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) {
                digest.update(buffer, 0, count);
            }
            return hex(digest.digest());
        }
    }

    private static String sha256(byte[] value) throws Exception {
        return hex(MessageDigest.getInstance("SHA-256").digest(value));
    }

    private static String hex(byte[] value) {
        StringBuilder result = new StringBuilder(value.length * 2);
        for (byte item : value) {
            result.append(String.format(Locale.US, "%02x", item & 0xff));
        }
        return result.toString();
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
}
