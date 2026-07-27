package cn.gaofeng.ambientops.kiosk;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class UiRevisionTrackerTest {
    private static final String REVISION_A = repeat("a");
    private static final String REVISION_B = repeat("b");
    private static final String REVISION_C = repeat("c");

    @Test
    public void firstObservationEstablishesBaseline() {
        UiRevisionTracker tracker = new UiRevisionTracker();

        assertFalse(tracker.observe(REVISION_A));
        assertFalse(tracker.observe(REVISION_A));
    }

    @Test
    public void changedRevisionRequiresTwoStableObservations() {
        UiRevisionTracker tracker = new UiRevisionTracker();
        tracker.observe(REVISION_A);

        assertFalse(tracker.observe(REVISION_B));
        assertTrue(tracker.observe(REVISION_B));
        assertFalse(tracker.observe(REVISION_B));
    }

    @Test
    public void unstableCandidateDoesNotReload() {
        UiRevisionTracker tracker = new UiRevisionTracker();
        tracker.observe(REVISION_A);

        assertFalse(tracker.observe(REVISION_B));
        assertFalse(tracker.observe(REVISION_C));
        assertFalse(tracker.observe(REVISION_B));
        assertTrue(tracker.observe(REVISION_B));
    }

    @Test
    public void returningToBaselineClearsCandidate() {
        UiRevisionTracker tracker = new UiRevisionTracker();
        tracker.observe(REVISION_A);

        assertFalse(tracker.observe(REVISION_B));
        assertFalse(tracker.observe(REVISION_A));
        assertFalse(tracker.observe(REVISION_B));
        assertTrue(tracker.observe(REVISION_B));
    }

    @Test
    public void endpointResetRequiresANewBaseline() {
        UiRevisionTracker tracker = new UiRevisionTracker();
        tracker.observe(REVISION_A);
        tracker.observe(REVISION_B);

        tracker.reset();

        assertFalse(tracker.observe(REVISION_B));
        assertFalse(tracker.observe(REVISION_B));
    }

    @Test
    public void invalidRevisionIsIgnored() {
        UiRevisionTracker tracker = new UiRevisionTracker();

        assertFalse(tracker.observe(null));
        assertFalse(tracker.observe("not-a-sha256"));
    }

    private static String repeat(String value) {
        return new String(new char[64]).replace("\0", value);
    }
}
