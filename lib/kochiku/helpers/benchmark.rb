# Benchmark
module Benchmark
  def benchmark(message)
    Kochiku::Worker.logger.info("[#{message}] starting")
    start_time = Time.now
    begin
      yield
    ensure
      duration = Time.now - start_time
      Kochiku::Worker.logger.info("[#{message}] finished in #{duration}")
    end
  end
end
