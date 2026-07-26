package cn.gaofeng.ambientops.kiosk;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;

import android.view.WindowManager;
import org.junit.Test;

public final class DisplayPowerPolicyTest {
    @Test
    public void keepsVisibleKioskAwakeWithoutWakingSleepingDevice() {
        int flags = DisplayPowerPolicy.windowFlags();

        assertNotEquals(0, flags & WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        assertNotEquals(0, flags & WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED);
        assertEquals(0, flags & WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
        assertEquals(0, flags & WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD);
    }
}
