package cn.gaofeng.ambientops.kiosk;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
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
    private static final long LOAD_TIMEOUT_MS = 10_000L;
    private static final long RESOLVE_TIMEOUT_MS = 5_000L;
    private static final long UPDATE_INITIAL_DELAY_MS = 10_000L;
    private static final long UPDATE_INTERVAL_MS = 6 * 60 * 60 * 1_000L;
    private static final float DEFAULT_SCREEN_BRIGHTNESS = 0.5f;
    private static final int IMMERSIVE_FLAGS =
        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            | View.SYSTEM_UI_FLAG_FULLSCREEN
            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private WebView webView;
    private ConnectivityManager connectivityManager;
    private ConnectivityManager.NetworkCallback networkCallback;
    private NsdManager nsdManager;
    private NsdManager.DiscoveryListener discoveryListener;
    private SharedPreferences preferences;
    private KioskUpdater kioskUpdater;
    private String currentEndpoint;
    private boolean pageLoaded;
    private boolean endpointAttemptInProgress;
    private boolean resolving;

    private final Runnable retry = () -> {
        String endpoint = preferredEndpoint();
        if (endpoint != null) {
            loadEndpoint(endpoint);
        } else {
            showDiscoveryState("正在查找 Ambient Ops");
            startDiscovery();
        }
    };
    private final Runnable loadTimeout = () -> {
        if (pageLoaded || !endpointAttemptInProgress || webView == null) {
            return;
        }
        webView.stopLoading();
        handleLoadFailure();
    };
    private final Runnable resolveTimeout = () -> {
        if (!resolving) {
            return;
        }
        resolving = false;
        stopDiscovery();
        handler.postDelayed(this::startDiscovery, RETRY_DELAY_MS);
    };
    private final Runnable updateCheck = new Runnable() {
        @Override
        public void run() {
            if (kioskUpdater != null && pageLoaded && currentEndpoint != null) {
                kioskUpdater.check(currentEndpoint);
            }
            handler.postDelayed(this, UPDATE_INTERVAL_MS);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(DisplayPowerPolicy.windowFlags());
        WindowManager.LayoutParams layout = getWindow().getAttributes();
        layout.screenBrightness = DEFAULT_SCREEN_BRIGHTNESS;
        getWindow().setAttributes(layout);
        enterImmersiveMode();

        preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        kioskUpdater = new KioskUpdater(this);
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
                verifyPageHealthy(view, url);
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

        String requestedUrl = getIntent() == null
            ? null
            : getIntent().getStringExtra(EXTRA_URL);
        currentEndpoint = validHttpUrl(requestedUrl)
            ? requestedUrl
            : preferredEndpoint();
        if (currentEndpoint != null) {
            loadEndpoint(currentEndpoint);
        } else {
            showDiscoveryState("正在查找 Ambient Ops");
        }
        startDiscovery();
        registerNetworkRetry();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        applyConfiguration(intent);
        String requestedUrl = intent == null ? null : intent.getStringExtra(EXTRA_URL);
        if (validHttpUrl(requestedUrl)) {
            loadEndpoint(requestedUrl);
        } else if (!pageLoaded && !endpointAttemptInProgress) {
            handler.post(retry);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        enterImmersiveMode();
        if (webView != null && !pageLoaded && !endpointAttemptInProgress) {
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
        unregisterNetworkRetry();
        stopDiscovery();
        if (kioskUpdater != null) {
            kioskUpdater.close();
            kioskUpdater = null;
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
        handler.removeCallbacks(resolveTimeout);
        handler.postDelayed(resolveTimeout, RESOLVE_TIMEOUT_MS);
        nsdManager.resolveService(serviceInfo, new NsdManager.ResolveListener() {
            @Override
            public void onResolveFailed(NsdServiceInfo failedService, int errorCode) {
                resolving = false;
                handler.removeCallbacks(resolveTimeout);
            }

            @Override
            public void onServiceResolved(NsdServiceInfo resolved) {
                handler.post(() -> handleResolvedService(resolved));
            }
        });
    }

    private void handleResolvedService(NsdServiceInfo resolved) {
        resolving = false;
        handler.removeCallbacks(resolveTimeout);
        String instanceId = attribute(resolved, "id");
        String preferredId = preferences.getString(PREF_INSTANCE_ID, null);
        boolean explicitBinding = validHttpUrl(
            preferences.getString(PREF_MANUAL_URL, null)
        );
        if (
            !ServiceSelectionPolicy.shouldAccept(
                preferredId,
                instanceId,
                pageLoaded || endpointAttemptInProgress,
                explicitBinding
            )
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
        endpointAttemptInProgress = true;
        handler.removeCallbacks(retry);
        handler.removeCallbacks(loadTimeout);
        handler.postDelayed(loadTimeout, LOAD_TIMEOUT_MS);
        webView.loadUrl(endpoint);
    }

    private void verifyPageHealthy(WebView view, String url) {
        if (!ServiceSelectionPolicy.shouldMarkPageHealthy(currentEndpoint, url)) {
            return;
        }
        view.evaluateJavascript(
            "document.getElementById('root') !== null",
            result -> {
                if (
                    view != webView
                        || !"true".equals(result)
                        || !ServiceSelectionPolicy.shouldMarkPageHealthy(
                            currentEndpoint,
                            url
                        )
                ) {
                    return;
                }
                pageLoaded = true;
                endpointAttemptInProgress = false;
                handler.removeCallbacks(retry);
                handler.removeCallbacks(loadTimeout);
                preferences.edit().putString(PREF_ENDPOINT, url).apply();
                handler.removeCallbacks(updateCheck);
                handler.postDelayed(updateCheck, UPDATE_INITIAL_DELAY_MS);
            }
        );
    }

    private void handleLoadFailure() {
        pageLoaded = false;
        endpointAttemptInProgress = false;
        handler.removeCallbacks(loadTimeout);
        handler.removeCallbacks(updateCheck);
        showDiscoveryState("Ambient Ops 暂时不可用，正在重新查找");
        startDiscovery();
        scheduleRetry();
    }

    private void scheduleRetry() {
        handler.removeCallbacks(retry);
        handler.postDelayed(retry, RETRY_DELAY_MS);
    }

    private void registerNetworkRetry() {
        connectivityManager =
            (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        if (connectivityManager == null) {
            return;
        }
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                handler.post(() -> {
                    if (!pageLoaded && !endpointAttemptInProgress) {
                        handler.post(retry);
                    }
                });
            }
        };
        try {
            connectivityManager.registerNetworkCallback(
                new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .build(),
                networkCallback
            );
        } catch (RuntimeException error) {
            networkCallback = null;
        }
    }

    private void unregisterNetworkRetry() {
        if (connectivityManager == null || networkCallback == null) {
            return;
        }
        try {
            connectivityManager.unregisterNetworkCallback(networkCallback);
        } catch (RuntimeException ignored) {
            // Android may already have released callbacks while shutting down.
        }
        networkCallback = null;
    }

    private String preferredEndpoint() {
        String manualUrl = preferences == null
            ? null
            : preferences.getString(PREF_MANUAL_URL, null);
        if (validHttpUrl(manualUrl)) {
            return manualUrl;
        }
        if (validHttpUrl(currentEndpoint)) {
            return currentEndpoint;
        }
        String rememberedEndpoint = preferences == null
            ? null
            : preferences.getString(PREF_ENDPOINT, null);
        return validHttpUrl(rememberedEndpoint) ? rememberedEndpoint : null;
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
}
