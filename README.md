# Fork of DelayedJob Sequel Backend

Forked from [delayed\_job\_sequel](https://github.com/TalentBox/delayed_job_sequel)

We've removed the following features to reduce deadlock when using MySQL.

* Job Priorities
* Expired job processing
* Own failed job processing

Creating the following index may be helpful

```sql
CREATE INDEX delayed_jobs_reserve ON delayed_jobs (queue, locked_at, failed_at, run_at);
```
