require 'sequel'
module Delayed
  module Backend
    module Sequel
      # A job object that is persisted to the database.
      # Contains the work object as a YAML field.
      class Job < ::Sequel::Model(::DelayedJobSequel.table_name)
        include Delayed::Backend::Base
        plugin :timestamps

        def before_save
          super
          set_default_run_at
        end

        def_dataset_method :ready_to_run do |worker_name|
          db_time_now = model.db_time_now
          filter do
            (
              (run_at <= db_time_now) &
              ::Sequel.expr(:locked_at => nil) |
              {:locked_by => worker_name}
            ) & {:failed_at => nil}
          end
        end

        def_dataset_method :by_priority do
          order(::Sequel.expr(:priority).asc, ::Sequel.expr(:run_at).asc)
        end

        def self.before_fork
          ::Sequel::Model.db.disconnect
        end

        # When a worker is exiting, make sure we don't have any locked jobs.
        def self.clear_locks!(worker_name)
          filter(:locked_by => worker_name).update(:locked_by => nil, :locked_at => nil)
        end

        # Find a few candidate jobs to run (in case some immediately get locked by others).
        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          ds = ready_to_run(worker_name)
          ds = ds.filter("priority >= ?", Worker.min_priority) if Worker.min_priority
          ds = ds.filter("priority <= ?", Worker.max_priority) if Worker.max_priority
          ds = ds.filter(:queue => Worker.queues) if Worker.queues.any?
          ds.by_priority.limit(limit).all
        end

        # Lock this job for this worker.
        # Returns true if we have the lock, false otherwise.
        def lock_exclusively!(max_run_time, worker)
          now           = self.class.db_time_now
          affected_rows = self.class.ready_to_run(worker).filter({ :id => pk }).update(:locked_at => now, :locked_by => worker)
          if affected_rows == 1
            self.locked_at = now
            self.locked_by = worker
            return true
          else
            return false
          end
        end

        # Get the current time (GMT or local depending on DB)
        # Note: This does not ping the DB to get the time, so all your clients
        # must have syncronized clocks.
        def self.db_time_now
          if Time.zone
            Time.zone.now
          elsif ::Sequel.database_timezone == :utc
            Time.now.utc
          else
            Time.now
          end
        end

        def self.delete_all
          dataset.delete
        end

        def reload(*args)
          reset
          super
        end

        def save!
          save :raise_on_failure => true
        end

        def update_attributes(attrs)
          update attrs
        end

        def self.create!(attrs)
          new(attrs).save :raise_on_failure => true
        end

        def self.silence_log(&block)
          if db.respond_to?(:logger) && db.logger.respond_to?(:silence)
            db.logger.silence &block
          else
            yield
          end
        end

        def self.count(attrs={})
          if attrs.respond_to?(:has_key?) && attrs.has_key?(:conditions)
            ds = self.where(attrs[:conditions])
            if attrs.has_key?(:group)
              column = attrs[:group]
              group_and_count(column.to_sym).map do |record|
                [record[column.to_sym], record[:count]]
              end
            else
              ds.count
            end
          else
            super()
          end
        end

        # The default behaviour for sequel on #==/#eql? is to check if all
        # values are matching.
        # This differs from ActiveRecord which checks class and id only.
        # To pass the specs we're reverting to what AR does here.
        def eql?(obj)
          (obj.class == self.class) && (obj.pk == pk)
        end

      end
    end
  end
end
