# frozen_string_literal: true

require 'rubygems'
require 'resque'
require 'resque/data_store'
require 'support/explicit_interface_implementation'

class FakeResqueDataStore
  extend ExplicitInterfaceImplementation
  implements Resque::DataStore

  QUEUES = lambda {
    {
      'foo' => [
        { 'class' => 'FooJob', 'args' => [1] },
        { 'class' => 'FooJob', 'args' => [2] },
        { 'class' => 'FooJob', 'args' => [3] },
        { 'class' => 'FooJob', 'args' => [4] },
        { 'class' => 'FooJob', 'args' => [5] }
      ],
      'bar' => [
        { 'class' => 'BarJob', 'args' => [1] },
        { 'class' => 'BarJob', 'args' => [2] }
      ]
    }
  }

  WORKERS = lambda {
    {
      mail: nil,
      cache: { 'queue' => 'cache',      'payload' => { 'class' => 'CacheJob', 'args' => ['whatever'] }, 'run_at' => (Time.now - 3600).iso8601 },
      generator: { 'queue' => 'generator', 'payload' => { 'class' => 'GeneratorJob', 'args' => ['yupyup'] }, 'run_at' => (Time.now - 60).iso8601 },
      purchasing: { 'queue' => 'purchasing', 'payload' => { 'class' => 'PurchasingJob', 'args' => ['blah'] }, 'run_at' => Time.now.iso8601 },
      indexing: { 'queue' => 'indexing', 'payload' => { 'class' => 'IndexingJob', 'args' => ['blah'] }, 'run_at' => 'mangled timestamp' }
    }
  }

  FAILED = lambda {
    [
      {
        'failed_at' => (Time.now.utc - 3600).iso8601,
        'payload' => {
          'class' => 'SomeFailingJob',
          'args' => [500_145, 1_114_130]
        },
        'exception' => 'Resque::TermException',
        'error' => 'SIGTERM',
        'backtrace' => [
          "/app/app/services/blah_whatever.rb:57:in `block in whatever!'",
          "/app/app/services/blah_whatever.rb:77:in `call'",
          "/app/app/services/blah_whatever.rb:77:in `with_whatever'",
          "/app/app/services/blah_whatever.rb:52:in `whatever!'",
          "/app/app/services/blah_whatever.rb:11:in `whatever_items_from_bleorgh'",
          "/app/lib/exceptions/exception_augmenter.rb:10:in `call'",
          "/app/lib/exceptions/exception_augmenter.rb:10:in `augment_all_exceptions_with'",
          "/app/app/jobs/concerns/whatevering_job.rb:6:in `augment_exceptions_with_remediation_help'",
          "/app/app/jobs/whatever_inconsistent_blagh_job.rb:8:in `perform'"
        ],
        'worker' => 'some_worker_id',
        'queue' => 'mail'
      },
      {
        'failed_at' => Time.now.utc.iso8601,
        'payload' => {
          'class' => 'SomeOtherFailingJob',
          'args' => ['blah']
        },
        'exception' => 'KeyError',
        'error' => "No Such key 'foobar'",
        'backtrace' => [
          "/app/app/services/blah_whatever.rb:57:in `block in whatever!'",
          "/app/app/services/blah_whatever.rb:77:in `call'",
          "/app/app/services/blah_whatever.rb:77:in `with_whatever'",
          "/app/app/jobs/concerns/whatevering_job.rb:6:in `augment_exceptions_with_remediation_help'",
          "/app/app/jobs/whatever_inconsistent_blagh_job.rb:8:in `perform'"
        ],
        'worker' => 'some_other_worker_id',
        'queue' => 'cache'
      },
      {
        'failed_at' => 'mangled time',
        'payload' => 'mangled payload'
      }
    ]
  }

  class FakeRedis
    def initialize(data)
      @data = data
    end

    def method_missing(sym, *args, &block)
      if @data[sym] && @data[sym].key?(args)
        @data[sym][args]
      else
        super
      end
    end
  end

  attr_reader :unregistered_workers,
              :failed,
              :queues

  def initialize(schedule: {})
    @unregistered_workers = []
    @failed = FAILED.call
    @queues = QUEUES.call
    @workers = WORKERS.call
    @fake_redis = if schedule.nil?
                    FakeRedis.new(hgetall: { ['schedules'] => nil })
                  elsif schedule.is_a?(Hash)
                    FakeRedis.new(hgetall: { ['schedules'] => schedule.map { |name, sched| [name.to_s, sched.to_json] }.to_h })
                  else
                    FakeRedis.new(hgetall: { ['schedules'] => schedule })
                  end
  end

  implement def queue_names
    @queues.keys
  end

  implement def queue_size(queue_name)
    @queues[queue_name].size
  end

  implement def num_failed(failed_queue_name = :failed)
    raise 'We do not support multiple failed queues' if failed_queue_name != :failed
    @failed.size
  end

  implement def worker_ids
    @workers.keys
  end

  implement def workers_map(worker_ids)
    Hash[@workers.select { |k, _v| worker_ids.include?(k) }.map do |k, v|
      ["worker:#{k}", Resque.encode(v)]
    end]
  end

  implement def everything_in_queue(queue)
    @queues[queue].map { |_| Resque.encode(_) }
  end

  implement def list_range(key, start = 0, count = 1)
    raise 'only failed is allowed' unless key == :failed
    result = @failed[start..(start + count - 1)].map { |_| Resque.encode(_) }
    if count == 1
      result.first
    else
      result
    end
  end

  implement def update_item_in_failed_queue(index, json, failed_queue_name = :failed)
    raise 'We do not support multiple failed queues' if failed_queue_name != :failed
    @failed[index] = Resque.decode(json)
  end

  implement def push_to_queue(queue, json)
    @queues[queue.to_s] ||= []
    @queues[queue.to_s] << Resque.decode(json)
  end

  implement def remove_from_failed_queue(index_in_failed_queue, failed_queue_name = :failed)
    raise 'We do not support multiple failed queues' if failed_queue_name != :failed
    @failed.delete_at(index_in_failed_queue)
  end

  implement def clear_failed_queue(failed_queue_name = :failed)
    raise 'We do not support multiple failed queues' if failed_queue_name != :failed
    @failed = []
  end

  implement_ghost! def hgetall(key)
    @fake_redis.hgetall(key)
  end
end
