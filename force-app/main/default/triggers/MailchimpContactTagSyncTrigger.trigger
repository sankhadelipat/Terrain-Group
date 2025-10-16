trigger MailchimpContactTagSyncTrigger on Contact_Tag__c(after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        Set<Id> tagIds = new Set<Id>();

        if (Trigger.isInsert || Trigger.isUndelete || Trigger.isUpdate) {
            for (Contact_Tag__c ct : Trigger.new) {
                tagIds.add(ct.Tag__c);
            }
        } else if (Trigger.isDelete) {
            for (Contact_Tag__c ct : Trigger.old) {
                tagIds.add(ct.Tag__c);
            }
        }

        if (!tagIds.isEmpty()) {
            System.enqueueJob(new MailchimpTagSyncQueueable('TAG_CONTACTS', tagIds));
        }
    }
}
