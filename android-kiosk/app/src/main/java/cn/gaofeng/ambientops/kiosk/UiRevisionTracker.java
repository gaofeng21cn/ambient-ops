package cn.gaofeng.ambientops.kiosk;

final class UiRevisionTracker {
    private static final int REQUIRED_CONFIRMATIONS = 2;

    private String baseline;
    private String candidate;
    private int confirmations;

    boolean observe(String revision) {
        if (revision == null || !revision.matches("[a-f0-9]{64}")) {
            return false;
        }
        if (baseline == null) {
            baseline = revision;
            clearCandidate();
            return false;
        }
        if (revision.equals(baseline)) {
            clearCandidate();
            return false;
        }
        if (!revision.equals(candidate)) {
            candidate = revision;
            confirmations = 1;
            return false;
        }
        confirmations += 1;
        if (confirmations < REQUIRED_CONFIRMATIONS) {
            return false;
        }
        baseline = revision;
        clearCandidate();
        return true;
    }

    void reset() {
        baseline = null;
        clearCandidate();
    }

    private void clearCandidate() {
        candidate = null;
        confirmations = 0;
    }
}
