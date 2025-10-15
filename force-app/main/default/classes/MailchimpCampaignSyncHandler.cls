public class MailchimpCampaignSyncHandler {
    // List of fields that trigger Mailchimp sync
    private static final Set<String> SYNC_FIELDS = new Set<String>{
        'Name',
        'Subject__c'
        // Add other fields as necessary
    };

    public static void syncCampaigns(List<Campaign> newCampaigns, Map<Id, Campaign> oldCampaignMap) {
        Set<Id> campaignIdsToProcess = new Set<Id>();

        for (Campaign newCamp : newCampaigns) {
            Campaign oldCamp = oldCampaignMap.get(newCamp.Id);

            Boolean shouldSync = false;

            // Check if any of the SYNC_FIELDS have changed
            for (String field : SYNC_FIELDS) {
                if (oldCamp.get(field) != newCamp.get(field)) {
                    shouldSync = true;
                    break;
                }
            }

            if (shouldSync) {
                campaignIdsToProcess.add(newCamp.Id);
            }
        }

        if (!campaignIdsToProcess.isEmpty()) {
            // Enqueue the Queueable job to sync campaigns
            System.enqueueJob(new MailchimpCampaignSyncQueueable('UPDATE', campaignIdsToProcess));
        }
    }
}
