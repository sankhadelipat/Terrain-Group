public class MailchimpTagPullBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = System.Label.MailChimpAudienceId;

    private Integer processedCount = 0;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private List<String> errorMessages = new List<String>();
    private List<String> mailchimpTagIds;

    // Constructor for initial batch
    public MailchimpTagPullBatch() {
        this.mailchimpTagIds = new List<String>();
    }

    // Constructor for processing specific tags
    public MailchimpTagPullBatch(List<String> tagIds) {
        this.mailchimpTagIds = tagIds;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        if (mailchimpTagIds.isEmpty()) {
            // Fetch all tag IDs from Mailchimp
            mailchimpTagIds = fetchAllMailchimpTagIds();
        }

        System.debug('Processing ' + mailchimpTagIds.size() + ' tags');
        return mailchimpTagIds;
    }

    public void execute(Database.BatchableContext bc, List<String> tagIds) {
        List<Tag__c> tagsToUpsert = new List<Tag__c>();

        for (String tagId : tagIds) {
            try {
                Http http = new Http();
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');
                req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments/' + tagId);
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Authorization', 'apikey ' + API_KEY);
                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                    String segmentId = String.valueOf(responseMap.get('id'));
                    String segmentName = String.valueOf(responseMap.get('name'));
                    Integer segmentCount = Integer.valueOf(responseMap.get('member_count'));

                    Tag__c tag = new Tag__c(
                        Name = segmentName,
                        Mailchimp_Tag_Id__c = segmentId,
                        Member_Count__c = segmentCount,
                        Sync_Status__c = 'Synced',
                        Last_Sync_Date__c = System.now()
                    );
                    tagsToUpsert.add(tag);
                    successCount++;
                } else {
                    errorCount++;
                    errorMessages.add(
                        'Error fetching tag ' + tagId + ': ' + res.getStatusCode() + ' - ' + res.getStatus()
                    );
                }

                // Add delay between callouts to avoid hitting limits
                addCalloutDelay();
            } catch (Exception e) {
                errorCount++;
                errorMessages.add('Error fetching tag ' + tagId + ': ' + e.getMessage());
                System.debug('Error fetching tag ' + tagId + ': ' + e.getMessage());
            } finally {
                processedCount++;
            }
        }

        if (!tagsToUpsert.isEmpty()) {
            try {
                upsert tagsToUpsert Mailchimp_Tag_Id__c;
                System.debug('Upserted ' + tagsToUpsert.size() + ' tags');
            } catch (DmlException dmlEx) {
                for (Tag__c tag : tagsToUpsert) {
                    errorMessages.add('Error upserting tag ' + tag.Name + ': ' + dmlEx.getMessage());
                }
            } finally {
                tagsToUpsert.clear();
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            'Batch Process Completed. Processed: ' +
                processedCount +
                ', Success: ' +
                successCount +
                ', Errors: ' +
                errorCount
        );

        if (!errorMessages.isEmpty()) {
            for (String errMsg : errorMessages) {
                System.debug('Error: ' + errMsg);
            }

            Logger__c log = new Logger__c(
                Name = 'Mailchimp Tag Pull Batch',
                Status__c = errorCount > 0 ? 'Failure' : 'Success',
                Message__c = 'Processed: ' +
                    processedCount +
                    ', Success: ' +
                    successCount +
                    ', Errors: ' +
                    errorCount +
                    (errorCount > 0 ? '. Check debug logs for details.' : ''),
                StackTrace__c = errorCount > 0 ? String.join(errorMessages, '\n') : null,
                Apex_Class__c = 'MailchimpTagPullBatch',
                Apex_Method__c = 'finish',
                Object_Name__c = 'Tag__c'
            );
            insert log;
        }
    }

    private List<String> fetchAllMailchimpTagIds() {
        List<String> tagIds = new List<String>();

        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments?count=1000&fields=segments.id&type=static');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'apikey ' + API_KEY);
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                List<Object> segments = (List<Object>) responseMap.get('segments');

                for (Object segmentObj : segments) {
                    Map<String, Object> segment = (Map<String, Object>) segmentObj;
                    String tagId = String.valueOf(segment.get('id'));
                    tagIds.add(tagId);
                }
            } else {
                System.debug('Error fetching Mailchimp tag IDs: ' + res.getStatusCode() + ' - ' + res.getStatus());

                errorMessages.add('Error fetching Mailchimp tag IDs: ' + res.getBody());
                errorCount++;
            }
        } catch (Exception e) {
            System.debug('Exception fetching tag IDs: ' + e.getMessage());
            errorMessages.add('Exception fetching tag IDs: ' + e.getMessage());
            errorCount++;
        }
        return tagIds;
    }

    private void addCalloutDelay() {
        if (Limits.getCallouts() < Limits.getLimitCallouts()) {
            Integer delay = 100; // 100ms delay
            Long startingTime = System.currentTimeMillis();
            while (System.currentTimeMillis() - startingTime < delay) {
                // Busy wait for the specified delay
            }
        }
    }
}
