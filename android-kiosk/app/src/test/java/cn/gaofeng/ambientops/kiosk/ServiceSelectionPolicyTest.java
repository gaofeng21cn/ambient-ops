package cn.gaofeng.ambientops.kiosk;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class ServiceSelectionPolicyTest {
    @Test
    public void healthyRememberedInstanceRejectsAnotherInstance() {
        assertFalse(
            ServiceSelectionPolicy.shouldAccept("home-ops", "backup-ops", true, false)
        );
    }

    @Test
    public void healthyRememberedInstanceAcceptsItsUpdatedEndpoint() {
        assertTrue(
            ServiceSelectionPolicy.shouldAccept("home-ops", "home-ops", true, false)
        );
    }

    @Test
    public void healthyRememberedInstanceRejectsAnonymousCandidate() {
        assertFalse(ServiceSelectionPolicy.shouldAccept("home-ops", null, true, false));
    }

    @Test
    public void failedPageAcceptsAnotherInstance() {
        assertTrue(
            ServiceSelectionPolicy.shouldAccept("home-ops", "backup-ops", false, false)
        );
    }

    @Test
    public void pendingRememberedEndpointRejectsAnotherInstance() {
        assertFalse(
            ServiceSelectionPolicy.shouldAccept("home-ops", "backup-ops", true, false)
        );
    }

    @Test
    public void firstHealthyDiscoveryIsAcceptedWithoutRememberedInstance() {
        assertTrue(ServiceSelectionPolicy.shouldAccept(null, "home-ops", true, false));
    }

    @Test
    public void explicitBindingRejectsFailoverAfterPageFailure() {
        assertFalse(
            ServiceSelectionPolicy.shouldAccept("home-ops", "backup-ops", false, true)
        );
    }

    @Test
    public void explicitBindingAcceptsSameInstanceAfterPageFailure() {
        assertTrue(
            ServiceSelectionPolicy.shouldAccept("home-ops", "home-ops", false, true)
        );
    }

    @Test
    public void explicitUrlWithoutInstanceIdRejectsDiscoveryReplacement() {
        assertFalse(ServiceSelectionPolicy.shouldAccept(null, "backup-ops", false, true));
    }

    @Test
    public void currentEndpointCompletionMarksPageHealthy() {
        assertTrue(
            ServiceSelectionPolicy.shouldMarkPageHealthy(
                "http://192.168.1.10:8791/display/overview",
                "http://192.168.1.10:8791/display/overview"
            )
        );
    }

    @Test
    public void staleEndpointCompletionDoesNotMarkNewEndpointHealthy() {
        assertFalse(
            ServiceSelectionPolicy.shouldMarkPageHealthy(
                "http://192.168.1.11:8791/display/overview",
                "http://192.168.1.10:8791/display/overview"
            )
        );
    }
}
