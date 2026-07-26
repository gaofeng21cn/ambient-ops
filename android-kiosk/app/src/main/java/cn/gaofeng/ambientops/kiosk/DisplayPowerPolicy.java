package cn.gaofeng.ambientops.kiosk;

import android.view.WindowManager;

final class DisplayPowerPolicy {
    private DisplayPowerPolicy() {}

    static int windowFlags() {
        return WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED;
    }
}
