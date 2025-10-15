trigger MailchimpCampaignMemberSyncTrigger on CampaignMember(after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        Set<Id> campaignIds = new Set<Id>();

        if (Trigger.isInsert || Trigger.isUndelete || Trigger.isUpdate) {
            for (CampaignMember cm : Trigger.new) {
                campaignIds.add(cm.CampaignId);
            }
        } else if (Trigger.isDelete) {
            for (CampaignMember cm : Trigger.old) {
                campaignIds.add(cm.CampaignId);
            }
        }

        if (!campaignIds.isEmpty()) {
            System.enqueueJob(new MailchimpCampaignSyncQueueable('UPDATE_MEMBERS', campaignIds));
        }
    }
}
