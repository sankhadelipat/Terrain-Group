public class MailchimpCampaignPullBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = System.Label.MailChimpAudienceId;

    private Integer processedCount = 0;
    private Integer successCount = 0;
    private Integer errorCount = 0;
    private List<String> errorMessages = new List<String>();
    private List<String> mailchimpCampaignIds;

    // Constructor for initial batch
    public MailchimpCampaignPullBatch() {
        this.mailchimpCampaignIds = new List<String>();
    }

    // Constructor for processing specific campaigns
    public MailchimpCampaignPullBatch(List<String> campaignIds) {
        this.mailchimpCampaignIds = campaignIds;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        if (mailchimpCampaignIds.isEmpty()) {
            // Fetch all campaign IDs from Mailchimp
            mailchimpCampaignIds = fetchAllMailchimpCampaignIds();
        }

        System.debug('Processing ' + mailchimpCampaignIds.size() + ' campaigns');
        return mailchimpCampaignIds;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        List<Campaign> campaignsToUpsert = new List<Campaign>();

        for (String campaignId : scope) {
            try {
                Http http = new Http();
                HttpRequest req = new HttpRequest();
                req.setMethod('GET');
                req.setEndpoint(BASE_URL + '/campaigns/' + campaignId);
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Authorization', 'apikey ' + API_KEY);
                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                    String mcCampaignId = String.valueOf(responseMap.get('id'));
                    String webId = String.valueOf(responseMap.get('web_id'));
                    String status = (String) responseMap.get('status');
                    String type = (String) responseMap.get('type');

                    Map<String, Object> settings = (Map<String, Object>) responseMap.get('settings');
                    String campaignName = settings != null && settings.containsKey('title')
                        ? (String) settings.get('title')
                        : 'Untitled Campaign';
                    String subject = settings != null && settings.containsKey('subject_line')
                        ? (String) settings.get('subject_line')
                        : 'No Subject';

                    Map<String, Object> recipients = (Map<String, Object>) responseMap.get('recipients');
                    String listId = recipients != null && recipients.containsKey('list_id')
                        ? (String) recipients.get('list_id')
                        : null;
                    String segmentId = extractSegmentId(recipients);

                    String sendTime = responseMap.get('send_time') != null
                        ? (String) responseMap.get('send_time')
                        : null;
                    DateTime sendDateTime = sendTime != null ? DateTime.valueOfGmt(sendTime) : null;

                    Campaign camp = new Campaign();
                    camp.Name = campaignName;
                    camp.Subject__c = subject;
                    camp.IsActive = (status == 'sent' || status == 'sending');
                    camp.StartDate = sendDateTime != null ? sendDateTime.date() : null;
                    // camp.EndDate = sendDateTime != null ? sendDateTime.date() : null;
                    camp.Mailchimp_Campaign_ID__c = mcCampaignId;
                    camp.Mailchimp_Web_ID__c = webId;
                    camp.Mailchimp_Segment_ID__c = segmentId;
                    camp.Status = mapMailchimpStatusToSalesforce(status);
                    camp.Type = mapMailchimpTypeToSalesforce(type);
                    camp.Sync_Status__c = 'Synced';
                    camp.Last_Sync_Date__c = Datetime.now();

                    campaignsToUpsert.add(camp);
                    successCount++;
                } else {
                    String errorMsg = 'Error fetching campaign ' + campaignId + ': ' + res.getBody();
                    System.debug(errorMsg);
                    errorMessages.add(errorMsg);
                    errorCount++;
                }

                // Add delay between callouts to avoid hitting limits
                addCalloutDelay();
            } catch (Exception e) {
                String errorMsg = 'Exception processing campaign ' + campaignId + ': ' + e.getMessage();
                System.debug(errorMsg);
                errorMessages.add(errorMsg);
                errorCount++;
            } finally {
                processedCount++;
            }
        }

        if (!campaignsToUpsert.isEmpty()) {
            try {
                upsert campaignsToUpsert Mailchimp_Campaign_ID__c;
                System.debug('Upserted ' + campaignsToUpsert.size() + ' campaigns');
            } catch (DmlException dmlEx) {
                for (Campaign c : campaignsToUpsert) {
                    errorMessages.add(
                        'DML Error upserting Campaign ID ' + c.Mailchimp_Campaign_ID__c + ': ' + dmlEx.getMessage()
                    );
                }
            } finally {
                campaignsToUpsert.clear();
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
                Name = 'Mailchimp Campaign Pull Batch',
                Status__c = errorCount > 0 ? 'Failure' : 'Success',
                Message__c = 'Processed: ' +
                    processedCount +
                    ', Success: ' +
                    successCount +
                    ', Errors: ' +
                    errorCount +
                    (errorCount > 0 ? '. Check debug logs for details.' : ''),
                StackTrace__c = errorCount > 0 ? String.join(errorMessages, '\n') : null,
                Apex_Class__c = 'MailchimpCampaignPullBatch',
                Apex_Method__c = 'finish',
                Object_Name__c = 'Campaign'
            );
            insert log;
        }
    }

    private List<String> fetchAllMailchimpCampaignIds() {
        List<String> campaignIds = new List<String>();

        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(BASE_URL + '/campaigns?count=1000&fields=campaigns.id,campaigns.recipients.list_id');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'apikey ' + API_KEY);
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if (responseMap.containsKey('campaigns')) {
                    List<Object> campaigns = (List<Object>) responseMap.get('campaigns');

                    for (Object obj : campaigns) {
                        Map<String, Object> campMap = (Map<String, Object>) obj;
                        Map<String, Object> recipients = (Map<String, Object>) campMap.get('recipients');

                        if (campMap.containsKey('id') && recipients != null) {
                            String listId = (String) recipients.get('list_id');
                            if (listId != null && listId == LIST_ID) {
                                campaignIds.add(String.valueOf(campMap.get('id')));
                            }
                        }
                    }
                }
            } else {
                String errorMsg = 'Error fetching campaign list: ' + res.getBody();
                System.debug(errorMsg);
                errorMessages.add(errorMsg);
                errorCount++;
            }
        } catch (Exception e) {
            String errorMsg = 'Exception fetching campaign list: ' + e.getMessage();
            System.debug(errorMsg);
            errorMessages.add(errorMsg);
            errorCount++;
        }
        return campaignIds;
    }

    // Helper method to extract segment ID from recipients
    private static String extractSegmentId(Map<String, Object> recipients) {
        if (recipients != null && recipients.containsKey('segment_opts')) {
            Map<String, Object> segmentOpts = (Map<String, Object>) recipients.get('segment_opts');
            if (segmentOpts.containsKey('saved_segment_id')) {
                return String.valueOf(segmentOpts.get('saved_segment_id'));
            }
        }
        return null;
    }

    // Map Mailchimp status to Salesforce status
    private static String mapMailchimpStatusToSalesforce(String mailchimpStatus) {
        switch on mailchimpStatus?.toLowerCase() {
            when 'save', 'paused', 'schedule' {
                return 'Planned';
            }
            when 'sending' {
                return 'In Progress';
            }
            when 'sent' {
                return 'Completed';
            }
            when 'canceled', 'canceling', 'archived' {
                return 'Aborted';
            }
            when else {
                return 'Planned';
            }
        }
    }

    // Map Mailchimp type to Salesforce type
    private static String mapMailchimpTypeToSalesforce(String mailchimpType) {
        switch on mailchimpType?.toLowerCase() {
            when 'regular', 'plaintext' {
                return 'Email';
            }
            when else {
                return 'Other';
            }
        }
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
