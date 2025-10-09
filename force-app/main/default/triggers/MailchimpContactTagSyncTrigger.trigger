trigger MailchimpContactTagSyncTrigger on Contact(after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        List<Contact> contactsToProcess = new List<Contact>();

        for (Contact con : Trigger.new) {
            Contact oldCon = Trigger.oldMap != null ? Trigger.oldMap.get(con.Id) : null;

            // Check if tags changed or it's a new contact
            if (oldCon == null || con.Tags__c != oldCon.Tags__c) {
                contactsToProcess.add(con);
            }
        }

        if (!contactsToProcess.isEmpty()) {
            MailchimpContactTagSyncHandler.syncTagsToMailchimp(contactsToProcess, Trigger.oldMap);
        }
    }
}
