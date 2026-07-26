package cn.gaofeng.ambientops.kiosk;

import org.json.JSONException;
import org.json.JSONObject;

final class UpdateMetadata {
    final long versionCode;
    final String versionName;
    final String apkPath;
    final String sha256;
    final String signerSha256;

    private UpdateMetadata(
        long versionCode,
        String versionName,
        String apkPath,
        String sha256,
        String signerSha256
    ) {
        this.versionCode = versionCode;
        this.versionName = versionName;
        this.apkPath = apkPath;
        this.sha256 = sha256;
        this.signerSha256 = signerSha256;
    }

    static UpdateMetadata parse(String body) throws JSONException {
        JSONObject json = new JSONObject(body);
        long versionCode = json.getLong("versionCode");
        String versionName = json.getString("versionName");
        String apkPath = json.getString("apkPath");
        String sha256 = normalizeSha256(json.getString("sha256"));
        String signerSha256 = normalizeSha256(json.getString("signerSha256"));
        if (versionCode <= 0) {
            throw new JSONException("versionCode must be positive");
        }
        if (!versionName.matches("^[a-zA-Z0-9._-]{1,40}$")) {
            throw new JSONException("versionName is invalid");
        }
        if (
            !apkPath.startsWith("/api/v1/kiosk/releases/")
                || apkPath.contains("..")
                || apkPath.contains("?")
                || apkPath.contains("#")
                || !apkPath.endsWith(".apk")
        ) {
            throw new JSONException("apkPath is invalid");
        }
        return new UpdateMetadata(
            versionCode,
            versionName,
            apkPath,
            sha256,
            signerSha256
        );
    }

    boolean isNewerThan(long installedVersionCode) {
        return versionCode > installedVersionCode;
    }

    private static String normalizeSha256(String value) throws JSONException {
        String normalized = value.trim().toLowerCase();
        if (!normalized.matches("^[a-f0-9]{64}$")) {
            throw new JSONException("SHA-256 is invalid");
        }
        return normalized;
    }
}
