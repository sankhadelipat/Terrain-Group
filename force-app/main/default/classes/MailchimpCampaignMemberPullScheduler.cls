public class MailchimpCampaignMemberPullScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        MailchimpCampaignMemberPullBatch batchJob = new MailchimpCampaignMemberPullBatch();
        Integer batchSize = 50;
        Database.executeBatch(batchJob, batchSize);
    }

    public static void scheduleCampaignMemberSync() {
        String jobName = 'MailchimpCampaignMemberSync';
        String cronExp = '0 30 * * * ?'; // Every 30 minutes
        MailchimpCampaignMemberPullScheduler schedule = new MailchimpCampaignMemberPullScheduler();
        System.schedule(jobName, cronExp, schedule);
    }
}
