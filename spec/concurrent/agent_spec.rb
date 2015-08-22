require_relative 'concern/observable_shared'

module Concurrent

  describe Agent do

    let!(:immediate) { Concurrent::ImmediateExecutor.new }
    let!(:executor) { Concurrent::SingleThreadExecutor.new }

    context 'initialization' do

      it 'sets the initial value' do
        subject = Agent.new(42)
        expect(subject.value).to eq 42
      end

      it 'sets the initial error to nil' do
        subject = Agent.new(42)
        expect(subject.error).to be nil
      end

      it 'sets the error mode when given a valid value' do
        subject = Agent.new(42, error_mode: :fail)
        expect(subject.error_mode).to eq :fail
      end

      it 'defaults the error mode to :continue when an error handler is given' do
        subject = Agent.new(42, error_handler: ->(value){ true })
        expect(subject.error_mode).to eq :continue
      end

      it 'defaults the error mode to :fail when no error handler is given' do
        subject = Agent.new(42)
        expect(subject.error_mode).to eq :fail
      end

      it 'raises an error when given an invalid error mode' do
        expect {
          Agent.new(42, error_mode: :bogus)
        }.to raise_error(ArgumentError)
      end

      it 'sets #failed? to false' do
        subject = Agent.new(42)
        expect(subject).to_not be_failed
        expect(subject).to_not be_stopped
      end
    end

    context 'action processing' do

      specify 'the given block will be passed the current value' do
        actual = nil
        expected = 0
        subject = Agent.new(expected)
        subject.send_via(immediate){|_, value, _| actual = value }
        expect(actual).to eq expected
      end

      specify 'the given block will be passed a reference to the agent' do
        actual = nil
        subject = Agent.new(0)
        subject.send_via(immediate){|agent, _, _| actual = agent }
        expect(actual).to eq subject
      end

      specify 'the given block will be passed any provided arguments' do
        actual = nil
        expected = [1, 2, 3, 4]
        subject = Agent.new(0)
        subject.send_via(immediate, *expected){|_, _, *args| actual = args }
        expect(actual).to eq expected
      end

      specify 'the return value will be passed to the validator function' do
        actual = nil
        expected = 42
        validator = ->(new_value){ actual = new_value; true }
        subject = Agent.new(0, validator: validator)
        subject.send_via(immediate){|_, _, _| expected }
        expect(actual).to eq expected
      end

      specify 'upon validation the new value will be set to the block return value' do
        actual = nil
        expected = 42
        validator = ->(new_value){ true }
        subject = Agent.new(0, validator: validator)
        subject.send_via(immediate){|_, _, _| expected }
        expect(subject.value).to eq expected
      end

      specify 'on success all observers will be notified' do
        observer_class = Class.new do
          def initialize(bucket)
            @bucket = bucket
          end
          def update(time, old_value, new_value)
            @bucket.concat([time, old_value, new_value])
          end
        end

        bucket = []
        subject = Agent.new(0)
        subject.add_observer(observer_class.new(bucket))
        subject.send_via(immediate){ 42 }

        expect(bucket[0]).to be_a Time
        expect(bucket[1]).to eq 0
        expect(bucket[2]).to eq 42
      end

      specify 'any recursive action dispatches will run after the value has been updated' do
        subject = Agent.new(0)

        subject.send_via(executor) do |a1, v1, _|
          expect(v1).to eq 0
          a1.send_via(executor) do |a2, v2, _|
            expect(v2).to eq 1
            a1.send_via(executor) do |a3, v3, _|
              expect(v3).to eq 2
              3
            end
            2
          end
          1
        end
      end

      specify 'when the action raises an error the value will not change' do
        expected = 0
        subject = Agent.new(expected)
        subject.send_via(immediate){|_, _, _| raise StandardError }
        expect(subject.value).to eq expected
      end

      specify 'when the action raises an error the validator will not be called' do
        validator_called = false
        validator = ->(new_value){ validator_called = true }
        subject = Agent.new(0, validator: validator)
        subject.send_via(immediate){|_, _, _| raise StandareError }
        expect(validator_called).to be false
      end

      specify 'when validation returns false the value will not change' do
        expected = 0
        validator = ->(new_value){ false }
        subject = Agent.new(0, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.value).to eq expected
      end

      specify 'when validation raises an error the value will not change' do
        expected = 0
        validator = ->(new_value){ raise StandareError }
        subject = Agent.new(0, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.value).to eq expected
      end

      specify 'when the action raises an error the handler will be called' do
        error_handler_called = false
        error_handler = ->(agent, exception){ error_handler_called = true }
        subject = Agent.new(0, error_handler: error_handler)
        subject.send_via(immediate){|_, _, _| raise StandardError }
        expect(error_handler_called).to be true
      end

      specify 'when validation fails the handler will be called' do
        error_handler_called = false
        error_handler = ->(agent, exception){ error_handler_called = true }
        validator = ->(new_value){ false }
        subject = Agent.new(0, error_handler: error_handler, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(error_handler_called).to be true
      end

      specify 'when validation raises an error the handler will be called' do
        error_handler_called = false
        error_handler = ->(agent, exception){ error_handler_called = true }
        validator = ->(new_value){ raise StandardError }
        subject = Agent.new(0, error_handler: error_handler, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(error_handler_called).to be true
      end
    end

    context 'validation' do

      it 'sets the new value when the validator returns true' do
        expected = 42
        validator = ->(new_value){ true }
        subject = Agent.new(0, validator: validator)
        subject.send_via(immediate){|_, _, _| expected }
        expect(subject.value).to eq expected
      end

      it 'rejects the new value when the validator returns false' do
        expected = 0
        validator = ->(new_value){ false }
        subject = Agent.new(expected, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.value).to eq expected
      end

      it 'rejects the new value when the validator raises an error' do
        expected = 0
        validator = ->(new_value){ raise StandardError }
        subject = Agent.new(expected, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.value).to eq expected
      end

      it 'sets the error when the error mode is :fail and the validator returns false' do
        validator = ->(new_value){ false }
        subject = Agent.new(0, error_mode: :fail, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.error).to be_a Agent::ValidationError
      end

      it 'sets the error when the error mode is :fail and the validator raises an error' do
        validator = ->(new_value){ raise expected }
        subject = Agent.new(0, error_mode: :fail, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.error).to be_a Agent::ValidationError
      end

      it 'does not set an error when the error mode is :continue and the validator returns false' do
        validator = ->(new_value){ false }
        subject = Agent.new(0, error_mode: :continue, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.error).to be nil
      end

      it 'does not set an error when the error mode is :continue and the validator raises an error' do
        validator = ->(new_value){ raise StandardError }
        subject = Agent.new(0, error_mode: :continue, validator: validator)
        subject.send_via(immediate){|_, _, _| 42 }
        expect(subject.error).to be nil
      end

      it 'does not trigger observation when validation fails' do
        observer_class = Class.new do
          attr_reader :count
          def initialize
            @count = 0
          end
          def update(time, old_value, new_value)
            @count += 1
          end
        end

        observer = observer_class.new
        subject = Agent.new(0, validator: ->(new_value){ false })
        subject.add_observer(observer)
        subject.send_via(immediate){ 42 }

        expect(observer.count).to eq 0
      end
    end

    context 'error handling' do

      specify 'the agent will be passed to the handler' do
        actual = nil
        error_handler = ->(agent, error){ actual = agent }
        subject = Agent.new(0, error_handler: error_handler)
        subject.send_via(immediate){|_, _, _| raise StandardError}
        expect(actual).to eq subject
      end

      specify 'the exception will be passed to the handler' do
        expected = StandardError.new
        actual = nil
        error_handler = ->(agent, error){ actual = error }
        subject = Agent.new(0, error_handler: error_handler)
        subject.send_via(immediate){|_, _, _| raise expected}
        expect(actual).to eq expected
      end

      specify 'does not trigger observation' do
        observer_class = Class.new do
          attr_reader :count
          def initialize
            @count = 0
          end
          def update(time, old_value, new_value)
            @count += 1
          end
        end

        observer = observer_class.new
        subject = Agent.new(0)
        subject.add_observer(observer)
        subject.send_via(immediate){ raise StandardError }

        expect(observer.count).to eq 0
      end
    end

    context 'error mode' do

      context ':continue' do

        it 'does not set an error when the validator returns false' do
          validator = ->(new_value){ false }
          subject = Agent.new(0, error_mode: :continue, validator: validator)
          subject.send_via(immediate){|_, _, _| 42 }
          expect(subject.error).to be nil
        end

        it 'does not set an error when the validator raises an error' do
          validator = ->(new_value){ raise StandardError }
          subject = Agent.new(0, error_mode: :continue, validator: validator)
          subject.send_via(immediate){|_, _, _| 42 }
          expect(subject.error).to be nil
        end

        it 'does not set an error when the action raises an error' do
          subject = Agent.new(0, error_mode: :continue)
          subject.send_via(immediate){|_, _, _| raise StandardError }
          expect(subject.error).to be nil
        end

        it 'does not block further action processing' do
          expected = 42
          actual = nil
          subject = Agent.new(0, error_mode: :continue)
          subject.send_via(immediate){|_, _, _| raise StandardError }
          subject.send_via(immediate){|_, _, _| 42 }
          expect(subject.value).to eq 42
        end

        it 'sets #failed? to false' do
          subject = Agent.new(0, error_mode: :continue)
          subject.send_via(immediate){|_, _, _| raise StandardError }
          expect(subject).to_not be_failed
        end
      end

      context ':fail' do

        it 'sets the error when the validator returns false' do
          validator = ->(new_value){ false }
          subject = Agent.new(0, error_mode: :fail, validator: validator)
          subject.send_via(immediate){|_, _, _,| 42 }
          expect(subject.error).to be_a Agent::ValidationError
        end

        it 'sets the error when the validator raises an error' do
          validator = ->(new_value){ raise expected }
          subject = Agent.new(0, error_mode: :fail, validator: validator)
          subject.send_via(immediate){|_, _, _,| 42 }
          expect(subject.error).to be_a Agent::ValidationError
        end

        it 'sets the error when the action raises an error' do
          expected = StandardError.new
          subject = Agent.new(0, error_mode: :fail)
          subject.send_via(immediate){|_, _, _,| raise expected }
          expect(subject.error).to eq expected
        end

        it 'blocks all further action processing until a restart' do
          latch = Concurrent::CountDownLatch.new
          expected = 42

          subject = Agent.new(0, error_mode: :fail)
          subject.send_via(immediate){|_, _, _| raise StandardError }
          subject.send_via(executor){|_, _, _,| latch.count_down; expected }

          latch.wait(0.1)
          expect(subject.value).to eq 0

          subject.restart(42)
          latch.wait(0.1)
          sleep(0.1)
          expect(subject.value).to eq expected
        end

        it 'sets #failed? to true' do
          subject = Agent.new(0, error_mode: :fail)
          subject.send_via(immediate){|_, _, _| raise StandardError }
          expect(subject).to be_failed
        end
      end
    end

    context 'nested actions' do

      specify 'occur in the order they ar post' do
        actual = []
        expected = [0, 1, 2, 3, 4]
        latch = Concurrent::CountDownLatch.new
        subject = Agent.new(0)

        subject.send_via(executor) do |a1, v1, _|
          a1.send_via(executor) do |a2, v2, _|
            a1.send_via(executor) do |a3, v3, _|
              a1.send_via(executor) do |a4, v4, _|
                a1.send_via(executor) do |a5, v5, _|
                  actual << v5; latch.count_down
                end
                actual << v4; v4 + 1
              end
              actual << v3; v3 + 1
            end
            actual << v2; v2 + 1
          end
          actual << v1; v1 + 1
        end

        latch.wait(2)
        expect(actual).to eq expected
      end

      specify 'work with immediate execution' do
        actual = []
        expected = [0, 1, 2]
        subject = Agent.new(0)

        subject.send_via(immediate) do |a1, v1, _|
          a1.send_via(immediate) do |a2, v2, _|
            a1.send_via(immediate) do |a3, v3, _|
              actual << v3
            end
            actual << v2; v2 + 1
          end
          actual << v1; v1 + 1
        end

        expect(actual).to eq expected
      end
    end

    context 'posting' do

      context 'with #send' do

        it 'returns true when the job is post' do
          subject = Agent.new(0)
          expect(subject.send{ nil }).to be true
        end

        it 'returns false when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect(subject.send{ nil }).to be false
        end

        it 'posts to the global fast executor' do
          expect(Concurrent.global_fast_executor).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject.send{ nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject.send{ sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end

      context 'with #send!' do

        it 'returns true when the job is post' do
          subject = Agent.new(0)
          expect(subject.send!{ nil }).to be true
        end

        it 'raises an error when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect {
            subject.send!{ nil }
          }.to raise_error(Agent::Error)
        end

        it 'posts to the global fast executor' do
          expect(Concurrent.global_fast_executor).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject.send!{ nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject.send!{ sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end

      context 'with #send_off' do

        it 'returns true when the job is post' do
          subject = Agent.new(0)
          expect(subject.send_off{ nil }).to be true
        end

        it 'returns false when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect(subject.send_off{ nil }).to be false
        end

        it 'posts to the global io executor' do
          expect(Concurrent.global_io_executor).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject.send_off{ nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject.send_off{ sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end

      context 'with #send_off!' do

        it 'returns true when the job is post' do
          subject = Agent.new(0)
          expect(subject.send_off!{ nil }).to be true
        end

        it 'raises an error when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect {
            subject.send_off!{ nil }
          }.to raise_error(Agent::Error)
        end

        it 'posts to the global io executor' do
          expect(Concurrent.global_io_executor).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject.send_off!{ nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject.send_off!{ sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end

      context 'with #send_via' do

        it 'returns true when the job is post' do
          subject = Agent.new(0)
          expect(subject.send_via(immediate){ nil }).to be true
        end

        it 'returns false when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect(subject.send_via(immediate){ nil }).to be false
        end

        it 'posts to the given executor' do
          expect(immediate).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject.send_via(immediate){ nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end

      context 'with #send_via!' do

        it 'returns true when the job is post' do
          subject = Agent.new(0)
          expect(subject.send_via!(immediate){ nil }).to be true
        end

        it 'raises an error when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect {
            subject.send_via!(immediate){ nil }
          }.to raise_error(Agent::Error)
        end

        it 'posts to the given executor' do
          expect(immediate).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject.send_via!(immediate){ nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject.send_via!(executor){ sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end

      context 'with #post' do

        it 'returns true when the job is post' do
          subject = Agent.new(0)
          expect(subject.post{ nil }).to be true
        end

        it 'returns false when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect(subject.post{ nil }).to be false
        end

        it 'posts to the global io executor' do
          expect(Concurrent.global_io_executor).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject.post{ nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject.post{ sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end

      context 'with #<<' do

        it 'returns self when the job is post' do
          subject = Agent.new(0)
          expect(subject << proc { nil }).to be subject
        end

        it 'returns self when #failed?' do
          subject = Agent.new(0)
          allow(subject).to receive(:failed?).and_return(true)
          expect(subject << proc { nil }).to be subject
        end

        it 'posts to the global io executor' do
          expect(Concurrent.global_io_executor).to receive(:post).with(any_args).and_call_original
          subject = Agent.new(0)
          subject << proc { nil }
        end

        it 'does not wait for the action to process' do
          job_done = false
          subject = Agent.new(0)
          subject << proc { sleep(5); job_done = true }
          expect(job_done).to be false
        end
      end
    end

    context '#restart' do

      context 'when #failed?' do

        it 'raises an error if the new value is not valid' do
          subject = Agent.new(0, error_mode: :fail, validator: ->(new_value){ false })
          subject.send_via(immediate){ raise StandardError }

          expect {
            subject.restart(0)
          }.to raise_error(Agent::Error)
        end

        it 'sets the new value' do
          subject = Agent.new(0, error_mode: :fail)
          subject.send_via(immediate){ raise StandardError }

          subject.restart(42)
          expect(subject.value).to eq 42
        end

        it 'clears the error' do
          subject = Agent.new(0, error_mode: :fail)
          subject.send_via(immediate){ raise StandardError }

          subject.restart(42)
          expect(subject.error).to be nil
        end

        it 'sets #failed? to true' do
          subject = Agent.new(0, error_mode: :fail)
          subject.send_via(immediate){ raise StandardError }

          subject.restart(42)
          expect(subject).to_not be_failed
        end

        it 'removes all actions from the queue when :clear_actions is true' do
          latch = Concurrent::CountDownLatch.new
          subject = Agent.new(0, error_mode: :fail)

          subject.send_via(executor){ latch.wait; raise StandardError }
          5.times{ subject.send_via(executor){ nil } }

          queue = subject.instance_variable_get(:@queue)
          expect(queue.size).to be > 0

          latch.count_down
          10.times{ break if subject.failed?; sleep(0.1) }

          subject.restart(42, clear_actions: true)
          expect(queue).to be_empty
        end

        it 'does not clear the action queue when :clear_actions is false' do
          latch = Concurrent::CountDownLatch.new
          subject = Agent.new(0, error_mode: :fail)

          subject.send_via(executor){ latch.wait; raise StandardError }
          5.times{ subject.send_via(executor){ nil } }

          queue = subject.instance_variable_get(:@queue)
          size = queue.size
          expect(size).to be > 0

          latch.count_down
          10.times{ break if subject.failed?; sleep(0.1) }

          subject.restart(42, clear_actions: false)
          expect(queue.size).to eq size-1
        end

        it 'does not clear the action queue when :clear_actions is not given' do
          latch = Concurrent::CountDownLatch.new
          subject = Agent.new(0, error_mode: :fail)

          subject.send_via(executor){ latch.wait; raise StandardError }
          5.times{ subject.send_via(executor){ nil } }

          queue = subject.instance_variable_get(:@queue)
          size = queue.size
          expect(size).to be > 0

          latch.count_down
          10.times{ break if subject.failed?; sleep(0.1) }

          subject.restart(42)
          expect(queue.size).to eq size-1
        end

        it 'resumes action processing if actions are enqueued' do
          count = 5
          latch = Concurrent::CountDownLatch.new
          finish_latch = Concurrent::CountDownLatch.new(5)
          subject = Agent.new(0, error_mode: :fail)

          subject.send_via(executor){ latch.wait; raise StandardError }
          count.times{ subject.send_via(executor){ finish_latch.count_down } }

          queue = subject.instance_variable_get(:@queue)
          size = queue.size
          expect(size).to be > 0

          latch.count_down
          10.times{ break if subject.failed?; sleep(0.1) }

          subject.restart(42, clear_actions: false)
          expect(finish_latch.wait(5)).to be true
        end

        it 'does not trigger observation' do
          observer_class = Class.new do
            attr_reader :count
            def initialize
              @count = 0
            end
            def update(time, old_value, new_value)
              @count += 1
            end
          end

          observer = observer_class.new
          subject = Agent.new(0, error_mode: :fail)
          subject.add_observer(observer)
          subject.send_via(immediate){ raise StandardError }
          subject.restart(42)

          expect(observer.count).to eq 0
        end
      end

      context 'when not #failed?' do

        it 'raises an error' do
          subject = Agent.new(0)
          expect {
            subject.restart(0)
          }.to raise_error(Agent::Error)
        end
      end
    end

    context 'waiting' do

      context 'the await job' do

        it 'does not change the value' do
          expected = 42
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(0.1); expected }
          subject.await_for(1)
          expect(subject.value).to eq expected
        end

        it 'does not trigger observers' do
          observer_class = Class.new do
            attr_reader :count
            def initialize
              @count = 0
            end
            def update(time, old_value, new_value)
              @count += 1
            end
          end

          observer = observer_class.new
          subject = Agent.new(0)
          subject.add_observer(observer)
          subject.send_via(executor){ sleep(0.1); 42 }
          subject.await_for(1)

          expect(observer.count).to eq 1
        end

        it 'waits for nested actions' do
          bucket = []
          latch = Concurrent::CountDownLatch.new
          executor = Concurrent::FixedThreadPool.new(3)
          subject = Agent.new(0)

          subject.send_via(executor) do |a1, _, _|
            a1.send_via(executor) do |a2, _, _|
              a2.send_via(executor) do |_, _, _|
                bucket << 3
              end
              latch.count_down
              sleep(0.2)
              bucket << 2
            end
            bucket << 1
          end
          latch.wait

          subject.await_for(5)
          expect(bucket).to eq [1, 2, 3]
        end
      end

      context 'with #await' do

        it 'returns true when there are no pending actions' do
          subject = Agent.new(0)
          expect(subject.await).to be true
        end

        it 'does not block on actions from other threads' do
          latch = Concurrent::CountDownLatch.new
          subject = Agent.new(0)
          t = Thread.new do
            subject.send_via(executor){ sleep }
            latch.count_down
          end

          latch.wait(0.1)
          ok = subject.await
          t.kill

          expect(ok).to be true
        end

        it 'blocks indefinitely' do
          start = Concurrent.monotonic_time
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          expect(subject.await).to be true
          expect(Concurrent.monotonic_time - start).to be > 0.5
        end

        it 'returns true when all prior actions have processed' do
          count = 0
          expected = 5
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          expected.times{ subject.send_via(executor){ count += 1 } }
          subject.await
          expect(count).to eq expected
        end

        it 'blocks forever if restarted with :clear_actions true', notravis: true do
          pending('the timing is nearly impossible'); fail
          subject = Agent.new(0, error_mode: :fail)

          t = Thread.new do
            subject.send_via(executor){ sleep(0.1) }
            subject.send_via(executor){ raise StandardError }
            subject.send_via(executor){ nil }
            Thread.new{ subject.restart(42, clear_actions: true) }
            subject.await
          end

          thread_status = t.join(0.3)
          t.kill

          expect(thread_status).to be nil
        end
      end

      context 'with #await_for' do

        it 'returns true when there are no pending actions' do
          subject = Agent.new(0)
          expect(subject.await_for(1)).to be true
        end

        it 'does not block on actions from other threads' do
          latch = Concurrent::CountDownLatch.new
          subject = Agent.new(0)
          t = Thread.new do
            subject.send_via(executor){ sleep }
            latch.count_down
          end

          latch.wait(0.1)
          ok = subject.await_for(0.1)
          t.kill

          expect(ok).to be true
        end

        it 'returns true when all prior actions have processed' do
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          5.times{ subject.send_via(executor){ nil } }
          expect(subject.await_for(10)).to be true
        end

        it 'returns false on timeout' do
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          5.times{ subject.send_via(executor){ nil } }
          expect(subject.await_for(0.1)).to be false
        end

        it 'returns false if restarted with :clear_actions true', notravis: true do
          pending('the timing is nearly impossible'); fail
          subject = Agent.new(0, error_mode: :fail)

          subject.send_via(executor){ sleep(0.1) }
          subject.send_via(executor){ raise StandardError }
          subject.send_via(executor){ nil }

          t = Thread.new{ subject.restart(42, clear_actions: true) }
          ok = subject.await_for(0.2)

          expect(ok).to be false
        end
      end

      context 'with #await_for!' do

        it 'returns true when there are no pending actions' do
          subject = Agent.new(0)
          expect(subject.await_for!(1)).to be true
        end

        it 'does not block on actions from other threads' do
          latch = Concurrent::CountDownLatch.new
          subject = Agent.new(0)
          t = Thread.new do
            subject.send_via(executor){ sleep }
            latch.count_down
          end

          latch.wait(0.1)
          ok = subject.await_for!(0.1)
          t.kill

          expect(ok).to be true
        end

        it 'returns true when all prior actions have processed' do
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          5.times{ subject.send_via(executor){ nil } }
          expect(subject.await_for!(10)).to be true
        end

        it 'raises an error on timeout' do
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          5.times{ subject.send_via(executor){ nil } }
          expect {
            subject.await_for!(0.1) 
          }.to raise_error(Concurrent::TimeoutError)
        end

        it 'raises an error if restarted with :clear_actions true', notravis: true do
          pending('the timing is nearly impossible'); fail
          subject = Agent.new(0, error_mode: :fail)

          subject.send_via(executor){ sleep(0.1) }
          subject.send_via(executor){ raise StandardError }
          subject.send_via(executor){ nil }

          t = Thread.new{ subject.restart(42, clear_actions: true) }

          expect {
            subject.await_for!(0.2) 
          }.to raise_error(Concurrent::TimeoutError)
        end
      end

      context 'with #wait' do

        it 'returns true when there are no pending actions and timeout is nil' do
          subject = Agent.new(0)
          expect(subject.wait(nil)).to be true
        end

        it 'returns true when there are no pending actions and a timeout is given' do
          subject = Agent.new(0)
          expect(subject.wait(1)).to be true
        end

        it 'does not block on actions from other threads' do
          latch = Concurrent::CountDownLatch.new
          subject = Agent.new(0)
          t = Thread.new do
            subject.send_via(executor){ sleep }
            latch.count_down
          end

          latch.wait(0.1)
          ok = subject.wait(0.1)
          t.kill

          expect(ok).to be true
        end

        it 'blocks indefinitely when timeout is nil' do
          start = Concurrent.monotonic_time
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          expect(subject.wait(nil)).to be true
          expect(Concurrent.monotonic_time - start).to be > 0.5
        end

        it 'blocks forever when timeout is nil and restarted with :clear_actions true', notravis: true do
          pending('the timing is nearly impossible'); fail
          subject = Agent.new(0, error_mode: :fail)

          t = Thread.new do
            subject.send_via(executor){ sleep(0.1) }
            subject.send_via(executor){ raise StandardError }
            subject.send_via(executor){ nil }
            Thread.new{ subject.restart(42, clear_actions: true) }
            subject.wait(nil)
          end

          thread_status = t.join(0.3)
          t.kill

          expect(thread_status).to be nil
        end

        it 'returns true when all prior actions have processed' do
          count = 0
          expected = 5
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          expected.times{ subject.send_via(executor){ count += 1 } }
          subject.wait(nil)
          expect(count).to eq expected
        end

        it 'returns false on timeout' do
          subject = Agent.new(0)
          subject.send_via(executor){ sleep(1) }
          5.times{ subject.send_via(executor){ nil } }
          expect(subject.wait(0.1)).to be false
        end

        it 'returns false when timeout is given and restarted with :clear_actions true', notravis: true do
          pending('the timing is nearly impossible'); fail
          subject = Agent.new(0, error_mode: :fail)

          subject.send_via(executor){ sleep(0.1) }
          subject.send_via(executor){ raise StandardError }
          subject.send_via(executor){ nil }

          t = Thread.new{ subject.restart(42, clear_actions: true) }
          ok = subject.wait(0.2)

          expect(ok).to be false
        end
      end

      context 'with .await' do

        it 'returns true when all prior actions on all agents have processed' do
          latch = Concurrent::CountDownLatch.new
          agents = 3.times.collect{ Agent.new(0) }
          agents.each{|agent| agent.send_via(executor, latch){|_, _, l| l.wait(1) } }
          Thread.new{ latch.count_down }
          ok = Agent.await(*agents)
          expect(ok).to be true
        end
      end

      context 'with .await_for' do

        it 'returns true when there are no pending actions' do
          agents = 3.times.collect{ Agent.new(0) }
          ok = Agent.await_for(1, *agents)
          expect(ok).to be true
        end

        it 'returns true when all prior actions for all agents have processed' do
          latch = Concurrent::CountDownLatch.new
          agents = 3.times.collect{ Agent.new(0) }
          agents.each{|agent| agent.send_via(executor, latch){|_, _, l| l.wait(1) } }
          Thread.new{ latch.count_down }
          ok = Agent.await_for(1, *agents)
          expect(ok).to be true
        end

        it 'returns false on timeout' do
          agents = 3.times.collect{ Agent.new(0) }
          agents.each{|agent| agent.send_via(executor){ sleep(0.3) } }
          ok = Agent.await_for(0.1, *agents)
          expect(ok).to be false
        end
      end

      context 'with await_for!' do

        it 'returns true when there are no pending actions' do
          agents = 3.times.collect{ Agent.new(0) }
          ok = Agent.await_for!(1, *agents)
          expect(ok).to be true
        end

        it 'returns true when all prior actions for all agents have processed' do
          latch = Concurrent::CountDownLatch.new
          agents = 3.times.collect{ Agent.new(0) }
          agents.each{|agent| agent.send_via(executor, latch){|_, _, l| l.wait(1) } }
          Thread.new{ latch.count_down }
          ok = Agent.await_for!(1, *agents)
          expect(ok).to be true
        end

        it 'raises an exception on timeout' do
          agents = 3.times.collect{ Agent.new(0) }
          agents.each{|agent| agent.send_via(executor){ sleep(0.3) } }
          expect {
            Agent.await_for!(0.1, *agents)
          }.to raise_error(Concurrent::TimeoutError)
        end
      end
    end

    context :observable do

      subject { Agent.new(0) }

      def trigger_observable(observable)
        observable.send_via(immediate){ 42 }
      end

      it_behaves_like :observable
    end
  end
end
