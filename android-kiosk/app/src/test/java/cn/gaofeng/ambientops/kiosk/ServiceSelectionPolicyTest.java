package cn.gaofeng.ambientops.kiosk;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class ServiceSelectionPolicyTest {
    @Test
    public void healthyRememberedInstanceRejectsAnotherInstance() {
        assertFalse(ServiceSelectionPolicy.shouldAccept("home-ops", "backup-ops", true));
    }

    @Test
    public void healthyRememberedInstanceAcceptsItsUpdatedEndpoint() {
        assertTrue(ServiceSelectionPolicy.shouldAccept("home-ops", "home-ops", true));
    }

    @Test
    public void healthyRememberedInstanceRejectsAnonymousCandidate() {
        assertFalse(ServiceSelectionPolicy.shouldAccept("home-ops", null, true));
    }

    @Test
    public void failedPageAcceptsAnotherInstance() {
        assertTrue(ServiceSelectionPolicy.shouldAccept("home-ops", "backup-ops", false));
    }

    @Test
    public void firstHealthyDiscoveryIsAcceptedWithoutRememberedInstance() {
        assertTrue(ServiceSelectionPolicy.shouldAccept(null, "home-ops", true));
    }
}
