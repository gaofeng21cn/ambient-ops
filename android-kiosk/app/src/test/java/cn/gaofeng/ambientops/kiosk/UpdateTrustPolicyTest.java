package cn.gaofeng.ambientops.kiosk;

import static org.junit.Assert.assertThrows;

import org.junit.Test;

public final class UpdateTrustPolicyTest {
    private static final String PACKAGE_NAME = "cn.gaofeng.ambientops.kiosk";
    private static final String SHA = "a".repeat(64);
    private static final String SIGNER =
        "4e5f5732645986e5a861446028846fcfb571b9dd006d87da19aa60f152639206";
    private static final UpdateMetadata UPDATE = update();

    @Test
    public void acceptsExactManifestAndCandidateIdentity() {
        UpdateTrustPolicy.requireTrustedManifest(UPDATE, SIGNER, SIGNER);
        UpdateTrustPolicy.requireTrustedCandidate(
            UPDATE,
            PACKAGE_NAME,
            PACKAGE_NAME,
            7,
            "1.2.3",
            SHA,
            SIGNER,
            SIGNER
        );
    }

    @Test
    public void rejectsManifestSignerMismatch() {
        assertThrows(
            SecurityException.class,
            () -> UpdateTrustPolicy.requireTrustedManifest(UPDATE, "b".repeat(64), SIGNER)
        );
    }

    @Test
    public void rejectsCandidateHashMismatch() {
        assertCandidateRejected(PACKAGE_NAME, 7, "1.2.3", "b".repeat(64), SIGNER);
    }

    @Test
    public void rejectsCandidatePackageMismatch() {
        assertCandidateRejected("cn.example.untrusted", 7, "1.2.3", SHA, SIGNER);
    }

    @Test
    public void rejectsCandidateVersionMismatch() {
        assertCandidateRejected(PACKAGE_NAME, 8, "1.2.3", SHA, SIGNER);
        assertCandidateRejected(PACKAGE_NAME, 7, "1.2.4", SHA, SIGNER);
    }

    @Test
    public void rejectsCandidateSignerMismatch() {
        assertCandidateRejected(PACKAGE_NAME, 7, "1.2.3", SHA, "b".repeat(64));
    }

    private static void assertCandidateRejected(
        String packageName,
        long versionCode,
        String versionName,
        String sha256,
        String signerSha256
    ) {
        assertThrows(
            SecurityException.class,
            () -> UpdateTrustPolicy.requireTrustedCandidate(
                UPDATE,
                PACKAGE_NAME,
                packageName,
                versionCode,
                versionName,
                sha256,
                signerSha256,
                SIGNER
            )
        );
    }

    private static UpdateMetadata update() {
        try {
            return UpdateMetadata.parse(
                "{"
                    + "\"versionCode\":7,"
                    + "\"versionName\":\"1.2.3\","
                    + "\"apkPath\":\"/api/v1/kiosk/releases/Ambient-Ops-Kiosk-1.2.3.apk\","
                    + "\"sha256\":\"" + SHA + "\","
                    + "\"signerSha256\":\"" + SIGNER + "\""
                    + "}"
            );
        } catch (Exception error) {
            throw new AssertionError(error);
        }
    }
}
