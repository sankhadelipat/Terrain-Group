@RestResource(urlMapping='/mailchimp/webhook')
global with sharing class MailchimpWebhook {
    // Mailchimp verification request (HEAD/GET)
    @HttpGet
    global static void verify() {
        RestResponse res = RestContext.response;
        res.statusCode = 200;
        res.responseBody = Blob.valueOf('Mailchimp Webhook Verified');
    }

    @HttpPost
    global static void handleWebhook() {
        // Mailchimp sends data as form-encoded, not JSON
        RestRequest req = RestContext.request;
        System.debug('Webhook request : ' + JSON.serializePretty(req));

        try {
            Map<String, String> params = req.params;
            String type = params.get('type');

            if (String.isBlank(type)) {
                System.debug('No type found in webhook payload.');
                return;
            }

            Map<String, Object> body = EncodedMapParser.normalize(params);
            System.debug('Webhook request body: ' + JSON.serializePretty(body));

            Map<String, Object> data = (Map<String, Object>) body.get('data');
            System.debug('Webhook type: ' + type);
            System.debug('Webhook data: ' + data);

            String email = (String) data.get('email');

            // Determine subscriber hash
            String subscriberHash;
            if (String.isNotBlank(email)) {
                subscriberHash = generateMD5Hash(email.toLowerCase());
            } else {
                System.debug('No email found in webhook payload.');
                return;
            }

            List<Mailchimp_Capture_Contact__e> capturedContacts = new List<Mailchimp_Capture_Contact__e>();
            if (type == 'subscribe' || type == 'profile' || type == 'upemail') {
                Mailchimp_Capture_Contact__e event = new Mailchimp_Capture_Contact__e();
                event.Operation__c = 'UPSERT';
                event.Mailchimp_Subscriber_Hash__c = subscriberHash;
                capturedContacts.add(event);
            } else if (type == 'unsubscribe' || type == 'cleaned') {
                Mailchimp_Capture_Contact__e event = new Mailchimp_Capture_Contact__e();
                event.Operation__c = 'DELETE';
                event.Mailchimp_Subscriber_Hash__c = subscriberHash;
                capturedContacts.add(event);
            }

            Database.saveResult[] results = EventBus.publish(capturedContacts);
            System.debug('Published: ' + results);
        } catch (Exception e) {
            System.debug('Error processing Mailchimp webhook: ' + e.getMessage());

            Logger__c log = new Logger__c(
                Name = 'Mailchimp Webhook Error',
                Status__c = 'Failure',
                Message__c = e.getMessage(),
                StackTrace__c = e.getStackTraceString(),
                Apex_Class__c = 'MailchimpWebhook',
                Apex_Method__c = 'handleWebhook',
                Object_Name__c = 'Mailchimp_Capture_Contact__e'
            );

            insert log;
        }
    }

    // Helper method to generate MD5 hash for Mailchimp member ID
    private static String generateMD5Hash(String input) {
        Blob targetBlob = Blob.valueOf(input);
        Blob md5hash = Crypto.generateDigest('MD5', targetBlob);
        return EncodingUtil.convertToHex(md5hash);
    }
}
