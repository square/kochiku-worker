class BuildStrategyFactory
  def self.get_strategy(strategy_name)
    case strategy_name
    when "random"
      BuildStrategy::LogAndRandomFailStrategy.new
    when "build_all"
      BuildStrategy::BuildAllStrategy.new
    else
      BuildStrategy::NoOpStrategy.new
    end
  end
end