public class MailchimpContactTagPullScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        MailchimpContactTagPullBatch batchJob = new MailchimpContactTagPullBatch();
        Integer batchSize = 50;
        Database.executeBatch(batchJob, batchSize);
    }

    public static void scheduleContactTagSync() {
        String jobName = 'MailchimpContactTagSync';
        String cronExp = '0 20 * * * ?'; // Every 20 minutes
        MailchimpContactTagPullScheduler schedule = new MailchimpContactTagPullScheduler();
        System.schedule(jobName, cronExp, schedule);
    }
}
