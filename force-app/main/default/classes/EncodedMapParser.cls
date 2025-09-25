public class EncodedMapParser {
    public static Map<String, Object> normalize(Map<String, String> flatMap) {
        Map<String, Object> result = new Map<String, Object>();

        for (String rawKey : flatMap.keySet()) {
            String value = flatMap.get(rawKey);

            // Extract keys: "data[merges][EMAIL]" → ["data","merges","EMAIL"]
            List<String> keys = new List<String>();
            Matcher m = Pattern.compile('([a-zA-Z0-9_]+)|\\[([a-zA-Z0-9_]+)\\]').matcher(rawKey);
            while (m.find()) {
                if (m.group(1) != null)
                    keys.add(m.group(1));
                else if (m.group(2) != null)
                    keys.add(m.group(2));
            }

            // If no brackets, then it's just a normal key
            if (keys.isEmpty()) {
                keys.add(rawKey);
            }

            insertNested(result, keys, value);
        }

        return result;
    }

    private static void insertNested(Map<String, Object> parent, List<String> keys, String value) {
        for (Integer i = 0; i < keys.size(); i++) {
            String k = keys[i];
            Boolean isLast = (i == keys.size() - 1);

            if (isLast) {
                parent.put(k, value);
            } else {
                if (!parent.containsKey(k) || !(parent.get(k) instanceof Map<String, Object>)) {
                    parent.put(k, new Map<String, Object>());
                }
                parent = (Map<String, Object>) parent.get(k);
            }
        }
    }
}
