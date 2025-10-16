public class MailchimpCampaignPullScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        MailchimpCampaignPullBatch batchJob = new MailchimpCampaignPullBatch();
        Integer batchSize = 50;
        Database.executeBatch(batchJob, batchSize);
    }

    public static void scheduleCampaignSync() {
        String jobName = 'MailchimpCampaignSync';
        String cronExp = '0 25 * * * ?'; // Every 25 minutes
        MailchimpCampaignPullScheduler schedule = new MailchimpCampaignPullScheduler();
        System.schedule(jobName, cronExp, schedule);
    }
}
