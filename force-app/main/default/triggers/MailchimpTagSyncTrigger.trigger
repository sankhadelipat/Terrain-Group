trigger MailchimpTagSyncTrigger on Tag__c(after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUndelete) {
            System.enqueueJob(new MailchimpTagSyncQueueable('INSERT', Trigger.newMap.keySet()));
        } else if (Trigger.isUpdate) {
            MailchimpTagSyncHandler.syncTags(Trigger.newMap, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            System.enqueueJob(new MailchimpTagSyncQueueable('DELETE', Trigger.oldMap.keySet()));
        }
    }
}
