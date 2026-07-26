package cn.gaofeng.ambientops.kiosk;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

public final class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "AmbientOpsUpdater";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (
            Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
        ) {
            Log.i(
                TAG,
                "event=runtime_restart action="
                    + action
                    + " versionCode="
                    + BuildConfig.VERSION_CODE
                    + " versionName="
                    + BuildConfig.VERSION_NAME
            );
            Intent launch = new Intent(context, MainActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            context.startActivity(launch);
        }
    }
}
