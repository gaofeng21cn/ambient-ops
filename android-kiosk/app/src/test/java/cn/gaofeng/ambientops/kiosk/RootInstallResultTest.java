package cn.gaofeng.ambientops.kiosk;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class RootInstallResultTest {
    @Test
    public void acceptsExactPackageManagerSuccess() {
        assertEquals(
            RootInstallResult.Status.SUCCESS,
            RootInstallResult.classify(false, 0, "Success\n")
        );
    }

    @Test
    public void identifiesOwnerGrantBoundary() {
        assertEquals(
            RootInstallResult.Status.OWNER_GRANT_REQUIRED,
            RootInstallResult.classify(true, -1, "")
        );
        assertEquals(
            RootInstallResult.Status.OWNER_GRANT_REQUIRED,
            RootInstallResult.classify(false, 1, "Permission denied")
        );
        assertEquals(
            RootInstallResult.Status.OWNER_GRANT_REQUIRED,
            RootInstallResult.classify(false, 1, "")
        );
    }

    @Test
    public void preservesPackageManagerFailure() {
        assertEquals(
            RootInstallResult.Status.FAILED,
            RootInstallResult.classify(
                false,
                1,
                "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]"
            )
        );
    }
}
