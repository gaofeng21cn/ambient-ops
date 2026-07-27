package cn.gaofeng.ambientops.kiosk;

import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONObject;

final class UiRevisionMonitor {
    private static final String TAG = "AmbientOpsUiRevision";
    private static final String REVISION_PATH = "/api/v1/ui/revision";
    private static final int CONNECT_TIMEOUT_MS = 5_000;
    private static final int READ_TIMEOUT_MS = 5_000;
    private static final int MAX_RESPONSE_BYTES = 16 * 1024;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean checking = new AtomicBoolean();
    private final UiRevisionTracker tracker = new UiRevisionTracker();
    private String selectedEndpoint;

    synchronized void selectEndpoint(String endpoint) {
        if (Objects.equals(selectedEndpoint, endpoint)) {
            return;
        }
        selectedEndpoint = endpoint;
        tracker.reset();
    }

    void check(String endpoint, Runnable onRevisionChanged) {
        selectEndpoint(endpoint);
        if (endpoint == null || !checking.compareAndSet(false, true)) {
            return;
        }
        executor.execute(() -> {
            try {
                String revision = readRevision(endpoint);
                boolean changed;
                synchronized (this) {
                    changed =
                        endpoint.equals(selectedEndpoint)
                            && tracker.observe(revision);
                }
                if (changed) {
                    onRevisionChanged.run();
                }
            } catch (Exception error) {
                Log.d(TAG, "UI revision check failed; keeping the current page", error);
            } finally {
                checking.set(false);
            }
        });
    }

    synchronized void close() {
        selectedEndpoint = null;
        tracker.reset();
        executor.shutdownNow();
    }

    private String readRevision(String endpoint) throws Exception {
        URL url = new URL(new URL(endpoint), REVISION_PATH);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(READ_TIMEOUT_MS);
        connection.setUseCaches(false);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("Cache-Control", "no-cache");
        connection.setRequestProperty("User-Agent", "AmbientOpsKiosk");
        try {
            int status = connection.getResponseCode();
            if (status != HttpURLConnection.HTTP_OK) {
                throw new IOException("UI revision endpoint returned HTTP " + status);
            }
            String body = new String(
                readLimited(connection.getInputStream()),
                StandardCharsets.UTF_8
            );
            String revision = new JSONObject(body)
                .optString("revision", "")
                .toLowerCase();
            if (!revision.matches("[a-f0-9]{64}")) {
                throw new IOException("UI revision response is invalid");
            }
            return revision;
        } finally {
            connection.disconnect();
        }
    }

    private byte[] readLimited(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[4 * 1024];
        int total = 0;
        int count;
        while ((count = input.read(buffer)) != -1) {
            total += count;
            if (total > MAX_RESPONSE_BYTES) {
                throw new IOException("UI revision response is too large");
            }
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }
}
