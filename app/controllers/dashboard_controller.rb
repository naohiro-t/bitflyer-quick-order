require 'bitflyer'
class DashboardController < ApplicationController
  before_action :set_agent

  def home
  end

  def buy
    puts "buy"
    puts params[:size]
    
  end

  def trade
    size = params[:size].to_f
    if params[:commit] == "BUY"
      if params[:size].empty?
        redirect_to :action => "home"
        flash[:alert] = 'Set size!!'
      else
        puts "BUY"
        buy(size)
      end
    elsif params[:commit] == "SELL"
      if params[:size].empty?
        redirect_to :action => "home"
        flash[:alert] = 'Set size!!'
      else
        puts "SELL"
        sell(size)
      end
    elsif params[:commit] == "CLOSE"
      puts "CLOSE"
      close
    end
    
    # @bitfly.buy(size_params)
    # flash[:success] = 'Your bought!'
  end

  private
    def set_agent
      @bitfly = BitFlyer.new
    end

    def buy(size)
      @bitfly.buy(size)
      redirect_to root_url, notice: 'You bought it!!' #flash: { success: "You bought it!!" }#flash[:success] = 'Your bought!'
    end

    def sell(size)
      @bitfly.sell(size)
      redirect_to root_url, notice: 'You sold it!!'
    end

    def close
      if @bitfly.close
        redirect_to root_url, notice: "Closed your postion!!"
      else
        redirect_to root_url, notice: "You didn't have any postion..."
      end
    end

end