package cn.gaofeng.ambientops.kiosk;

final class UpdateTrustPolicy {
    private UpdateTrustPolicy() {}

    static void requireTrustedManifest(
        UpdateMetadata update,
        String installedSignerSha256,
        String expectedSignerSha256
    ) {
        if (
            !expectedSignerSha256.equals(installedSignerSha256)
                || !expectedSignerSha256.equals(update.signerSha256)
        ) {
            throw new SecurityException("Installed app or update manifest signer is not trusted");
        }
    }

    static void requireTrustedCandidate(
        UpdateMetadata update,
        String expectedPackageName,
        String candidatePackageName,
        long candidateVersionCode,
        String candidateVersionName,
        String candidateSha256,
        String candidateSignerSha256,
        String expectedSignerSha256
    ) {
        if (!update.sha256.equals(candidateSha256)) {
            throw new SecurityException("Downloaded APK SHA-256 does not match the manifest");
        }
        if (!expectedPackageName.equals(candidatePackageName)) {
            throw new SecurityException("Downloaded APK package name is not trusted");
        }
        if (
            candidateVersionCode != update.versionCode
                || !update.versionName.equals(candidateVersionName)
        ) {
            throw new SecurityException("Downloaded APK version does not match the manifest");
        }
        if (!expectedSignerSha256.equals(candidateSignerSha256)) {
            throw new SecurityException("Downloaded APK signer is not trusted");
        }
    }
}
