trigger MailchimpContactTrigger on Contact(after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUndelete) {
            System.enqueueJob(new MailchimpContactSyncQueueable('UPSERT', Trigger.newMap.keySet()));
        } else if (Trigger.isUpdate) {
            MailchimpContactSyncHandler.syncContacts(Trigger.newMap, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            System.enqueueJob(new MailchimpContactSyncQueueable('DELETE', Trigger.oldMap.keySet()));
        }
    }
}
