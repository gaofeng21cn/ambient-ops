package cn.gaofeng.ambientops.kiosk;

final class ServiceSelectionPolicy {
    private ServiceSelectionPolicy() {}

    static boolean shouldAccept(
        String rememberedInstanceId,
        String candidateInstanceId,
        boolean keepRememberedInstance,
        boolean explicitBinding
    ) {
        if (explicitBinding) {
            return rememberedInstanceId != null
                && rememberedInstanceId.equals(candidateInstanceId);
        }
        if (!keepRememberedInstance || rememberedInstanceId == null) {
            return true;
        }
        return rememberedInstanceId.equals(candidateInstanceId);
    }

    static boolean shouldMarkPageHealthy(String currentEndpoint, String finishedUrl) {
        return currentEndpoint != null && currentEndpoint.equals(finishedUrl);
    }
}
