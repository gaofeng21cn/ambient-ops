package cn.gaofeng.ambientops.kiosk;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

final class ServiceSelectionPolicy {
    private ServiceSelectionPolicy() {}

    static DisplaySource automaticSource(
        List<DisplaySource> sources,
        String rememberedSourceId
    ) {
        if (rememberedSourceId != null) {
            for (DisplaySource source : sources) {
                if (rememberedSourceId.equals(source.id)) {
                    return source;
                }
            }
        }

        List<DisplaySource> gateways = new ArrayList<>();
        List<DisplaySource> direct = new ArrayList<>();
        for (DisplaySource source : sources) {
            if (source.kind == DisplaySource.Kind.GATEWAY) {
                gateways.add(source);
            } else {
                direct.add(source);
            }
        }
        if (!gateways.isEmpty()) {
            gateways.sort(Comparator.comparing(source -> source.name, String.CASE_INSENSITIVE_ORDER));
            return gateways.get(0);
        }
        return direct.size() == 1 ? direct.get(0) : null;
    }

    static boolean shouldMarkPageHealthy(String currentEndpoint, String finishedUrl) {
        return currentEndpoint != null && currentEndpoint.equals(finishedUrl);
    }
}
