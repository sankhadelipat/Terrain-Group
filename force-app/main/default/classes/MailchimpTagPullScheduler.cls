public class MailchimpTagPullScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        MailchimpTagPullBatch batchJob = new MailchimpTagPullBatch();
        Integer batchSize = 50;
        Database.executeBatch(batchJob, batchSize);
    }

    public static void scheduleTagSync() {
        String jobName = 'MailchimpTagSync';
        String cronExp = '0 15 * * * ?'; // Every 15 minutes
        MailchimpTagPullScheduler schedule = new MailchimpTagPullScheduler();
        System.schedule(jobName, cronExp, schedule);
    }
}
