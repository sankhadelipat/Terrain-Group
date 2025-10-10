public class MailchimpContactTagPullScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        MailchimpContactTagPullBatch batchJob = new MailchimpContactTagPullBatch();
        Integer batchSize = 50;
        Database.executeBatch(batchJob, batchSize);
    }

    public static void scheduleBatch() {
        String jobName = 'MailchimpContactTagPullBatchJob';
        String cronExp = '0 15 * * * ?'; // Every 15 minutes
        MailchimpContactTagPullScheduler schedule = new MailchimpContactTagPullScheduler();
        System.schedule(jobName, cronExp, schedule);
    }
}
