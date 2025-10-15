public class MailchimpCampaignSyncQueueable implements Queueable, Database.AllowsCallouts {
    private Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private String API_KEY = auth.Mailchimp_API_Key__c;
    private String BASE_URL = auth.Mailchimp_Base_URL__c;
    private String LIST_ID = '23ad32226b';
    private static final String DEFAULT_FROM_NAME = 'Your Company';
    private static final String DEFAULT_FROM_EMAIL = 'sankha.delipat@gmail.com';

    private String operation; // 'INSERT', 'UPDATE' or 'DELETE'
    private Set<Id> recordIds;

    public MailchimpCampaignSyncQueueable(String op, Set<Id> ids) {
        this.operation = op;
        this.recordIds = ids;
    }

    public void execute(QueueableContext context) {
        List<Campaign> campaignsToSync = new List<Campaign>();
        // Query Campaigns with neessary fields
        List<Campaign> campaigns = [
            SELECT
                Id,
                Name,
                Type,
                Status,
                StartDate,
                EndDate,
                ExpectedRevenue,
                BudgetedCost,
                ActualCost,
                Description,
                Subject__c,
                Mailchimp_Campaign_ID__c
            FROM Campaign
            WHERE Id IN :recordIds
        ];

        try {
            // Prepare HTTP request
            Http http = new Http();

            for (Campaign camp : campaigns) {
                HttpRequest req = new HttpRequest();

                if (operation == 'INSERT' || operation == 'UPDATE_MEMBERS') {
                    // Get all campaign member emails
                    List<String> memberEmails = getCampaignMemberEmails(camp.Id);

                    // Create or update segment with exact campaign members
                    String segmentId = MailchimpCampaignManager.createOrUpdateCampaignSegment(
                        camp.Id,
                        camp.Name,
                        memberEmails
                    );

                    if (camp.Mailchimp_Campaign_ID__c != null) {
                        // Update existing campaign to use new segment
                        String requestBody = JSON.serialize(
                            new Map<String, Object>{
                                'recipients' => new Map<String, Object>{
                                    'segment_opts' => new Map<String, Object>{
                                        'saved_segment_id' => Integer.valueOf(segmentId)
                                    }
                                }
                            }
                        );

                        req.setEndpoint(BASE_URL + '/campaigns/' + camp.Mailchimp_Campaign_ID__c);
                        req.setHeader('Content-Type', 'application/json');
                        req.setHeader('Authorization', 'apikey ' + API_KEY);
                        req.setMethod('PATCH');
                        req.setBody(requestBody);
                    } else {
                        // Build the JSON Body for Mailchimp
                        Map<String, Object> body = new Map<String, Object>{
                            'type' => 'regular',
                            'recipients' => new Map<String, Object>{
                                'list_id' => LIST_ID,
                                'segment_opts' => new Map<String, Object>{
                                    'saved_segment_id' => Integer.valueOf(segmentId)
                                }
                            },
                            'settings' => new Map<String, Object>{
                                'subject_line' => camp.Subject__c != null ? camp.Subject__c : 'No Subject',
                                'title' => camp.Name != null ? camp.Name : 'Untitled Campaign',
                                'from_name' => DEFAULT_FROM_NAME,
                                'reply_to' => DEFAULT_FROM_EMAIL,
                                'to_name' => '*|FNAME|*',
                                'auto_footer' => false
                            }
                        };

                        req.setEndpoint(BASE_URL + '/campaigns');
                        req.setHeader('Content-Type', 'application/json');
                        req.setHeader('Authorization', 'apikey ' + API_KEY);
                        req.setMethod('POST');
                        req.setBody(JSON.serialize(body));
                    }
                } else if (operation == 'UPDATE') {
                    if (String.isBlank(camp.Mailchimp_Campaign_ID__c)) {
                        System.debug('Skipping campaign update with no Mailchimp Campaign ID: ' + camp.Id);
                        continue;
                    }
                    // Build the JSON Body for Mailchimp
                    Map<String, Object> body = new Map<String, Object>{
                        'settings' => new Map<String, Object>{
                            'subject_line' => camp.Subject__c != null ? camp.Subject__c : 'No Subject',
                            'title' => camp.Name != null ? camp.Name : 'Untitled Campaign',
                            'from_name' => DEFAULT_FROM_NAME,
                            'reply_to' => DEFAULT_FROM_EMAIL,
                            'to_name' => '*|FNAME|*',
                            'auto_footer' => false
                        }
                    };
                    req.setEndpoint(BASE_URL + '/campaigns');
                    req.setHeader('Content-Type', 'application/json');
                    req.setHeader('Authorization', 'apikey ' + API_KEY);
                    req.setMethod('PATCH');
                    req.setBody(JSON.serialize(body));
                } else if (operation == 'DELETE') {
                    if (String.isBlank(camp.Mailchimp_Campaign_ID__c)) {
                        System.debug('Skipping campaign delete with no Mailchimp Campaign ID: ' + camp.Id);
                        continue;
                    }
                    req.setEndpoint(BASE_URL + '/campaigns/' + camp.Mailchimp_Campaign_ID__c);
                    req.setHeader('Authorization', 'apikey ' + API_KEY);
                    req.setMethod('DELETE');
                }

                HttpResponse res = http.send(req);
                System.debug('Mailchimp Response: ' + res.getBody());

                if (res.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String mailchimpId = String.valueOf(responseMap.get('id'));
                    String webId = String.valueOf(responseMap.get('web_id'));
                    Map<String, Object> recipients = (Map<String, Object>) responseMap.get('recipients');
                    String segmentId = recipients != null && recipients.containsKey('segment_opts')
                        ? String.valueOf(((Map<String, Object>) recipients.get('segment_opts')).get('saved_segment_id'))
                        : null;

                    if (operation == 'INSERT') {
                        Campaign updatedCamp = new Campaign(
                            Id = camp.Id,
                            Mailchimp_Campaign_ID__c = mailchimpId,
                            Mailchimp_Web_ID__c = webId,
                            Mailchimp_Segment_ID__c = segmentId,
                            Sync_Status__c = 'Synced',
                            Last_Sync_Date__c = Datetime.now()
                        );

                        campaignsToSync.add(updatedCamp);
                    }
                    //   else if (operation == 'DELETE') {
                    //   }
                } else {
                    Campaign failedCamp = new Campaign(Id = camp.Id, Sync_Status__c = 'Failed');
                    campaignsToSync.add(failedCamp);

                    System.debug(
                        'Failed to sync campaign: ' +
                            camp.Id +
                            ', Status: ' +
                            res.getStatusCode() +
                            ', Body: ' +
                            res.getBody()
                    );
                    throw new CalloutException('Failed to sync campaign: ' + camp.Id);
                }
            }

            if (!campaignsToSync.isEmpty()) {
                update campaignsToSync;
            }
        } catch (Exception e) {
            System.debug('Error syncing campaigns: ' + e.getMessage());

            Logger__c log = new Logger__c(
                Name = 'Mailchimp Campaign Sync Error',
                Status__c = 'Failure',
                Message__c = e.getMessage(),
                StackTrace__c = e.getStackTraceString(),
                Apex_Class__c = 'MailchimpCampaignSyncQueueable',
                Apex_Method__c = 'execute',
                Object_Name__c = 'Campaign'
            );
            insert log;
        }
    }

    // Get all member emails from a Salesforce campaign
    private static List<String> getCampaignMemberEmails(Id campaignId) {
        List<String> emails = new List<String>();

        List<CampaignMember> members = [
            SELECT Contact.Email, ContactId
            FROM CampaignMember
            WHERE CampaignId = :campaignId AND Contact.Email != NULL
        ];

        for (CampaignMember member : members) {
            emails.add(member.Contact.Email);
        }

        return emails;
    }
}
