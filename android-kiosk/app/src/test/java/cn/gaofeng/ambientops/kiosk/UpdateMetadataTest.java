package cn.gaofeng.ambientops.kiosk;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.json.JSONException;
import org.junit.Test;

public final class UpdateMetadataTest {
    private static final String SHA = "a".repeat(64);
    private static final String SIGNER =
        "4e5f5732645986e5a861446028846fcfb571b9dd006d87da19aa60f152639206";

    @Test
    public void parsesAValidSameOriginUpdate() throws Exception {
        UpdateMetadata update = UpdateMetadata.parse(
            "{"
                + "\"versionCode\":5,"
                + "\"versionName\":\"1.2.1\","
                + "\"apkPath\":\"/api/v1/kiosk/releases/Ambient-Ops-Kiosk-1.2.1.apk\","
                + "\"sha256\":\"" + SHA + "\","
                + "\"signerSha256\":\"" + SIGNER + "\""
                + "}"
        );

        assertEquals(5, update.versionCode);
        assertEquals("1.2.1", update.versionName);
        assertTrue(update.isNewerThan(4));
        assertFalse(update.isNewerThan(5));
    }

    @Test
    public void rejectsTraversalAndMalformedDigests() {
        assertThrows(
            JSONException.class,
            () -> UpdateMetadata.parse(
                "{"
                    + "\"versionCode\":5,"
                    + "\"versionName\":\"1.2.1\","
                    + "\"apkPath\":\"/api/v1/kiosk/releases/../bad.apk\","
                    + "\"sha256\":\"" + SHA + "\","
                    + "\"signerSha256\":\"" + SIGNER + "\""
                    + "}"
            )
        );
        assertThrows(
            JSONException.class,
            () -> UpdateMetadata.parse(
                "{"
                    + "\"versionCode\":5,"
                    + "\"versionName\":\"1.2.1\","
                    + "\"apkPath\":\"/api/v1/kiosk/releases/update.apk\","
                    + "\"sha256\":\"short\","
                    + "\"signerSha256\":\"" + SIGNER + "\""
                    + "}"
            )
        );
    }
}
