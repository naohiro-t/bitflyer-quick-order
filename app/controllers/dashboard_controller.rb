require 'bitflyer'
class DashboardController < ApplicationController
  before_action :set_agent

  def home
    @ticker = @bitfly.get_ticker
    @positions = @bitfly.get_position
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
      completed = @bitfly.buy(size)
      if completed
        redirect_to root_url, notice: 'You bought it!!' #flash: { success: "You bought it!!" }#flash[:success] = 'Your bought!'
      else
        redirect_to root_url, alert: 'Tried 3 times but failed to complete it!!' #flash: { success: "You bought it!!" }#flash[:success] = 'Your bought!'
      end
    end

    def sell(size)
      completed = @bitfly.sell(size)
      if completed
        redirect_to root_url, notice: 'You sold it!!' #flash: { success: "You bought it!!" }#flash[:success] = 'Your bought!'
      else
        redirect_to root_url, alert: 'Tried 3 times but failed to complete it!!' #flash: { success: "You bought it!!" }#flash[:success] = 'Your bought!'
      end
    end

    def close
      if @bitfly.close
        redirect_to root_url, notice: "Closed your postion!!"
      else
        redirect_to root_url, notice: "You didn't have any postion..."
      end
    end

end