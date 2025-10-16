public class MailchimpCampaignManager {
    private static Mailchimp_Auth__c auth = Mailchimp_Auth__c.getOrgDefaults();
    private static String API_KEY = auth.Mailchimp_API_Key__c;
    private static String BASE_URL = auth.Mailchimp_Base_URL__c;
    private static String LIST_ID = '23ad32226b';

    // Create or update segment for Salesforce campaign
    public static String createOrUpdateCampaignSegment(
        String campaignId,
        String campaignName,
        List<String> memberEmails
    ) {
        try {
            // Generate segment name based on Salesforce campaign
            String segmentName = 'SF_Campaign_' + campaignName.replace(' ', '_') + '_' + campaignId;

            // Check if segment already exists
            String existingSegmentId = getSegmentIdByName(segmentName);

            if (existingSegmentId != null) {
                // Update existing segment
                updateSegmentMembers(existingSegmentId, memberEmails);
                return existingSegmentId;
            } else {
                // Create new segment
                return createSegmentWithMembers(segmentName, memberEmails);
            }
        } catch (Exception e) {
            throw e;
        }
    }

    // Create new segment with specific members
    private static String createSegmentWithMembers(String segmentName, List<String> memberEmails) {
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'apikey ' + API_KEY);

            // First create a static segment
            String requestBody = JSON.serialize(
                new Map<String, Object>{ 'name' => segmentName, 'static_segment' => memberEmails }
            );
            req.setBody(requestBody);

            HttpResponse res = http.send(req);
            System.debug('Mailchimp Create Segment Response: ' + res.getBody());

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String segmentId = String.valueOf(responseMap.get('id'));
                return segmentId;
            } else {
                System.debug('Error creating segment: ' + res.getBody());
                throw new CalloutException('Error creating segment');
            }
        } catch (Exception e) {
            throw e;
        }
    }

    // Update segment members (add/remove as needed)
    public static void updateSegmentMembers(String segmentId, List<String> newMemberEmails) {
        try {
            // Get current segment members
            Set<String> currentMembers = getSegmentMembers(segmentId);
            Set<String> newMembers = new Set<String>(newMemberEmails);

            // Find members to add
            Set<String> membersToAdd = new Set<String>();
            for (String email : newMembers) {
                if (!currentMembers.contains(email)) {
                    membersToAdd.add(email);
                }
            }

            // Find members to remove
            Set<String> membersToRemove = new Set<String>();
            for (String email : currentMembers) {
                if (!newMembers.contains(email)) {
                    membersToRemove.add(email);
                }
            }

            // Add or remove members
            addOrRemoveMembersFromSegment(segmentId, new List<String>(membersToAdd), new List<String>(membersToRemove));
        } catch (Exception e) {
            throw e;
        }
    }

    // Add or Remove members from existing segment
    private static void addOrRemoveMembersFromSegment(
        String segmentId,
        List<String> emailsToAdd,
        List<String> emailsToRemove
    ) {
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments/' + segmentId);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'apikey ' + API_KEY);

            // Add or remove members
            Map<String, Object> body = new Map<String, Object>();
            if (!emailsToAdd.isEmpty()) {
                body.put('members_to_add', emailsToAdd);
            }
            if (!emailsToRemove.isEmpty()) {
                body.put('members_to_remove', emailsToRemove);
            }
            String requestBody = JSON.serialize(body);
            req.setBody(requestBody);

            HttpResponse res = http.send(req);
            System.debug('Mailchimp Add or Remove Members Response: ' + res.getBody());

            if (res.getStatusCode() == 200) {
                System.debug('Successfully added ' + emailsToAdd.size() + ' members to segment');
                System.debug('Successfully removed ' + emailsToRemove.size() + ' members from segment');
            } else {
                System.debug('Error adding/removing members from segment: ' + res.getBody());
                throw new CalloutException('Error adding/removing members from segment');
            }
        } catch (Exception e) {
            throw e;
        }
    }

    // Get segment ID by name
    public static String getSegmentIdByName(String segmentName) {
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments?count=1000');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'apikey ' + API_KEY);

            HttpResponse res = http.send(req);
            System.debug('Mailchimp Get Segment Response: ' + res.getBody());

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> segments = (List<Object>) responseMap.get('segments');

                for (Object segmentObj : segments) {
                    Map<String, Object> segment = (Map<String, Object>) segmentObj;
                    if (segment.get('name') == segmentName) {
                        return String.valueOf(segment.get('id'));
                    }
                }
            } else {
                System.debug('Error fetching segments: ' + res.getBody());
                throw new CalloutException('Error fetching segment ID by name');
            }
        } catch (Exception e) {
            throw e;
        }
        return null;
    }

    // Get current segment members
    public static Set<String> getSegmentMembers(String segmentId) {
        Set<String> members = new Set<String>();

        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(BASE_URL + '/lists/' + LIST_ID + '/segments/' + segmentId + '/members?count=1000');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'apikey ' + API_KEY);

            HttpResponse res = http.send(req);
            System.debug('Mailchimp Get Segment Response: ' + res.getBody());

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> memberList = (List<Object>) responseMap.get('members');

                for (Object memberObj : memberList) {
                    Map<String, Object> member = (Map<String, Object>) memberObj;
                    members.add((String) member.get('email_address'));
                }
            } else {
                System.debug('Error fetching segment members: ' + res.getBody());
                throw new CalloutException('Error fetching segment members');
            }
        } catch (Exception e) {
            throw e;
        }

        return members;
    }
}
