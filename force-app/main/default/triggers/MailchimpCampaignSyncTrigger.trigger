trigger MailchimpCampaignSyncTrigger on Campaign(after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUndelete) {
            System.enqueueJob(new MailchimpCampaignSyncQueueable('INSERT', Trigger.newMap.keySet()));
        } else if (Trigger.isUpdate) {
            MailchimpCampaignSyncHandler.syncCampaigns(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            System.enqueueJob(new MailchimpCampaignSyncQueueable('DELETE', Trigger.oldMap.keySet()));
        }
    }
}
