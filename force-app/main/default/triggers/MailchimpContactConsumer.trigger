trigger MailchimpContactConsumer on Mailchimp_Capture_Contact__e(after insert) {
    for (Mailchimp_Capture_Contact__e event : Trigger.new) {
        System.enqueueJob(new MailchimpContactCreateQueueable(event.Operation__c, event.Mailchimp_Subscriber_Hash__c));
    }
}
