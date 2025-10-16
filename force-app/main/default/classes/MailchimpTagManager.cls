public class MailchimpTagManager {
    public static List<String> getTagMemberEmails(Id tagId) {
        List<String> memberEmails = new List<String>();

        List<Contact> contacts = [
            SELECT Email
            FROM Contact
            WHERE
                Id IN (
                    SELECT Contact__c
                    FROM Contact_Tag__c
                    WHERE Tag__c = :tagId
                )
                AND Email != NULL
        ];

        for (Contact con : contacts) {
            memberEmails.add(con.Email);
        }

        return memberEmails;
    }
}
