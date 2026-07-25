package cn.gaofeng.ambientops.kiosk;

import android.app.Activity;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Map;

public final class MainActivity extends Activity {
    private static final String SERVICE_TYPE = "_ambient-ops._tcp.";
    private static final String DEFAULT_PATH = "/display/overview";
    private static final String PREFS = "ambient_ops_kiosk";
    private static final String PREF_ENDPOINT = "last_endpoint";
    private static final String PREF_INSTANCE_ID = "last_instance_id";
    private static final String PREF_MANUAL_URL = "manual_url";
    private static final String EXTRA_URL = "ambient_ops_url";
    private static final String EXTRA_INSTANCE_ID = "ambient_ops_instance_id";
    private static final long RETRY_DELAY_MS = 2_000L;
    private static final int IMMERSIVE_FLAGS =
        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            | View.SYSTEM_UI_FLAG_FULLSCREEN
            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private WebView webView;
    private PowerManager.WakeLock wakeLock;
    private NsdManager nsdManager;
    private NsdManager.DiscoveryListener discoveryListener;
    private SharedPreferences preferences;
    private String currentEndpoint;
    private boolean pageLoaded;
    private boolean resolving;

    private final Runnable retry = () -> {
        if (currentEndpoint != null) {
            loadEndpoint(currentEndpoint);
        } else {
            showDiscoveryState("正在查找 Ambient Ops");
            startDiscovery();
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                | WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        );
        wakeScreen();
        enterImmersiveMode();

        preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        applyConfiguration(getIntent());
        nsdManager = (NsdManager) getSystemService(Context.NSD_SERVICE);

        webView = new WebView(this);
        webView.setBackgroundColor(Color.rgb(12, 15, 18));
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setMediaPlaybackRequiresUserGesture(false);
        webView.getSettings().setUserAgentString(
            webView.getSettings().getUserAgentString() + " AmbientOpsKiosk/1.1"
        );
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                if (url != null && url.startsWith("http")) {
                    pageLoaded = true;
                    handler.removeCallbacks(retry);
                    preferences.edit().putString(PREF_ENDPOINT, url).apply();
                }
                enterImmersiveMode();
            }

            @Override
            public void onReceivedError(
                WebView view,
                WebResourceRequest request,
                WebResourceError error
            ) {
                if (request.isForMainFrame()) {
                    handleLoadFailure();
                }
            }

            @Override
            public void onReceivedHttpError(
                WebView view,
                WebResourceRequest request,
                WebResourceResponse errorResponse
            ) {
                if (request.isForMainFrame()) {
                    handleLoadFailure();
                }
            }
        });
        setContentView(webView);

        String rememberedEndpoint = preferences.getString(PREF_ENDPOINT, null);
        String manualUrl = preferences.getString(PREF_MANUAL_URL, null);
        currentEndpoint = validHttpUrl(rememberedEndpoint)
            ? rememberedEndpoint
            : validHttpUrl(manualUrl) ? manualUrl : null;
        if (currentEndpoint != null) {
            loadEndpoint(currentEndpoint);
        } else {
            showDiscoveryState("正在查找 Ambient Ops");
        }
        startDiscovery();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (applyConfiguration(intent)) {
            String manualUrl = preferences.getString(PREF_MANUAL_URL, null);
            if (validHttpUrl(manualUrl)) {
                loadEndpoint(manualUrl);
            }
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        enterImmersiveMode();
        if (webView != null && webView.getUrl() == null) {
            handler.post(retry);
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            enterImmersiveMode();
        }
    }

    @Override
    public void onBackPressed() {
        if (currentEndpoint != null) {
            loadEndpoint(currentEndpoint);
        }
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        stopDiscovery();
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }

    private void startDiscovery() {
        if (nsdManager == null || discoveryListener != null) {
            return;
        }
        discoveryListener = new NsdManager.DiscoveryListener() {
            @Override
            public void onDiscoveryStarted(String serviceType) {}

            @Override
            public void onServiceFound(NsdServiceInfo serviceInfo) {
                if (SERVICE_TYPE.equals(serviceInfo.getServiceType()) && !resolving) {
                    resolveService(serviceInfo);
                }
            }

            @Override
            public void onServiceLost(NsdServiceInfo serviceInfo) {}

            @Override
            public void onDiscoveryStopped(String serviceType) {}

            @Override
            public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                stopDiscovery();
                scheduleRetry();
            }

            @Override
            public void onStopDiscoveryFailed(String serviceType, int errorCode) {
                discoveryListener = null;
            }
        };
        try {
            nsdManager.discoverServices(
                SERVICE_TYPE,
                NsdManager.PROTOCOL_DNS_SD,
                discoveryListener
            );
        } catch (RuntimeException error) {
            discoveryListener = null;
            scheduleRetry();
        }
    }

    private void stopDiscovery() {
        if (nsdManager == null || discoveryListener == null) {
            return;
        }
        NsdManager.DiscoveryListener listener = discoveryListener;
        discoveryListener = null;
        try {
            nsdManager.stopServiceDiscovery(listener);
        } catch (IllegalArgumentException ignored) {
            // Android may already have stopped discovery after a network transition.
        }
    }

    private void resolveService(NsdServiceInfo serviceInfo) {
        resolving = true;
        nsdManager.resolveService(serviceInfo, new NsdManager.ResolveListener() {
            @Override
            public void onResolveFailed(NsdServiceInfo failedService, int errorCode) {
                resolving = false;
            }

            @Override
            public void onServiceResolved(NsdServiceInfo resolved) {
                handler.post(() -> handleResolvedService(resolved));
            }
        });
    }

    private void handleResolvedService(NsdServiceInfo resolved) {
        resolving = false;
        String instanceId = attribute(resolved, "id");
        String preferredId = preferences.getString(PREF_INSTANCE_ID, null);
        if (
            preferredId != null
                && instanceId != null
                && !preferredId.equals(instanceId)
                && pageLoaded
        ) {
            return;
        }

        String endpoint = endpoint(resolved);
        if (endpoint == null) {
            return;
        }
        SharedPreferences.Editor editor = preferences.edit()
            .putString(PREF_ENDPOINT, endpoint);
        if (instanceId != null) {
            editor.putString(PREF_INSTANCE_ID, instanceId);
        }
        editor.apply();

        if (!endpoint.equals(currentEndpoint) || !pageLoaded) {
            loadEndpoint(endpoint);
        }
    }

    private String endpoint(NsdServiceInfo serviceInfo) {
        InetAddress host = serviceInfo.getHost();
        int port = serviceInfo.getPort();
        if (host == null || port <= 0) {
            return null;
        }
        String address = host.getHostAddress();
        if (address == null || address.isEmpty()) {
            return null;
        }
        if (address.contains(":")) {
            address = "[" + address.replaceAll("%.*$", "") + "]";
        }
        String path = attribute(serviceInfo, "path");
        if (path == null || !path.startsWith("/")) {
            path = DEFAULT_PATH;
        }
        return String.format(Locale.US, "http://%s:%d%s", address, port, path);
    }

    private String attribute(NsdServiceInfo serviceInfo, String key) {
        Map<String, byte[]> attributes = serviceInfo.getAttributes();
        byte[] value = attributes.get(key);
        return value == null ? null : new String(value, StandardCharsets.UTF_8);
    }

    private void loadEndpoint(String endpoint) {
        if (!validHttpUrl(endpoint)) {
            return;
        }
        currentEndpoint = endpoint;
        pageLoaded = false;
        handler.removeCallbacks(retry);
        webView.loadUrl(endpoint);
    }

    private void handleLoadFailure() {
        pageLoaded = false;
        currentEndpoint = null;
        preferences.edit().remove(PREF_ENDPOINT).apply();
        showDiscoveryState("Ambient Ops 暂时不可用，正在重新查找");
        startDiscovery();
        scheduleRetry();
    }

    private void scheduleRetry() {
        handler.removeCallbacks(retry);
        handler.postDelayed(retry, RETRY_DELAY_MS);
    }

    private void showDiscoveryState(String message) {
        if (webView == null) {
            return;
        }
        String html =
            "<!doctype html><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
                + "<style>html,body{height:100%;margin:0;background:#0c0f12;color:#eef3f7;"
                + "font-family:sans-serif}body{display:grid;place-items:center}"
                + "main{text-align:center}strong{font-size:32px;font-weight:500}"
                + "p{font-size:18px;color:#9aa5ae}</style><main><strong>"
                + escapeHtml(message)
                + "</strong><p>_ambient-ops._tcp.local</p></main>";
        webView.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
    }

    private boolean applyConfiguration(Intent intent) {
        if (intent == null) {
            return false;
        }
        String url = intent.getStringExtra(EXTRA_URL);
        String instanceId = intent.getStringExtra(EXTRA_INSTANCE_ID);
        SharedPreferences.Editor editor = getSharedPreferences(PREFS, MODE_PRIVATE).edit();
        boolean changed = false;
        if (validHttpUrl(url)) {
            editor.putString(PREF_MANUAL_URL, url);
            changed = true;
        }
        if (instanceId != null && instanceId.matches("[A-Za-z0-9._-]{1,80}")) {
            editor.putString(PREF_INSTANCE_ID, instanceId.toLowerCase(Locale.US));
            changed = true;
        }
        if (changed) {
            editor.apply();
        }
        return changed;
    }

    private boolean validHttpUrl(String value) {
        return value != null
            && (value.startsWith("http://") || value.startsWith("https://"));
    }

    private String escapeHtml(String value) {
        return value
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;");
    }

    private void enterImmersiveMode() {
        getWindow().getDecorView().setSystemUiVisibility(IMMERSIVE_FLAGS);
    }

    @SuppressWarnings("deprecation")
    private void wakeScreen() {
        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK
                | PowerManager.ACQUIRE_CAUSES_WAKEUP
                | PowerManager.ON_AFTER_RELEASE,
            "AmbientOps:KioskDisplay"
        );
        wakeLock.acquire();

        KeyguardManager keyguardManager =
            (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        keyguardManager.requestDismissKeyguard(this, null);
    }
}
