package cn.gaofeng.ambientops.kiosk;

final class RootInstallResult {
    enum Status {
        SUCCESS,
        OWNER_GRANT_REQUIRED,
        FAILED,
    }

    private RootInstallResult() {}

    static Status classify(boolean timedOut, int exitCode, String output) {
        if (timedOut) {
            return Status.OWNER_GRANT_REQUIRED;
        }
        String normalized = output == null ? "" : output.trim().toLowerCase();
        if (exitCode == 0 && "success".equals(normalized)) {
            return Status.SUCCESS;
        }
        if (
            normalized.isEmpty()
                || normalized.contains("permission denied")
                || normalized.contains("not allowed")
                || normalized.contains("access denied")
        ) {
            return Status.OWNER_GRANT_REQUIRED;
        }
        return Status.FAILED;
    }
}
