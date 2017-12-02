#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'openssl'
require 'json'

class BitFlyer
  def initialize#(size, confirm_line, loss_cut_line)
    @uri = URI.parse("https://api.bitflyer.jp")
    @https = Net::HTTP.new(@uri.host, @uri.port)
    @https.use_ssl = true
    @key = ENV['BITFLYER_API_KEY']
    @secret = ENV['BITFLYER_SECRET_KEY']
    # @size = size.to_f
    # @confirm_line = confirm_line.to_f
    # if loss_cut_line.to_f > 0
    #   @loss_cut_line = loss_cut_line.to_f * -1
    # else   
    #   @loss_cut_line = loss_cut_line.to_f
    # end
  end

  def buy(size)
    ticker = get_ticker
    price = ticker["best_bid"].to_i + 100
    order_id = order_child("LIMIT", "BUY", size, price)
    confirm_order(order_id)
  end

  def sell(size)
    ticker = get_ticker
    price = ticker["best_ask"].to_i - 100
    order_id = order_child("LIMIT", "SELL", size, price)
    confirm_order(order_id)
  end

  def close
    positions = get_position
    size = 0.0
    side = ""
    puts positions
    # positions.each do |position|
    #   side = position['side']
    # end
    positions.each do |position|
      side = position['side']
      size = size + position['size'].to_f
    end
    if size == 0 #no position
      return false 
    elsif side == "SELL" #holding short
      order_child("MARKET", "BUY", size, price)
    elsif side == "BUY" #holding long
      order_child("MARKET", "SELL", size, price)
    end
    return true # close completed
  end

  def get_product_list
    @uri.path = '/v1/markets'
    @uri.query = ''
    response = @https.get @uri.request_uri
    JSON.parse(response.body)
  end

  def get_board
    @uri.path = '/v1/getboard'
    @uri.query = 'product_code=FX_BTC_JPY'
    response = @https.get @uri.request_uri
    JSON.parse(response.body)
  end
  
  # {"product_code"=>"FX_BTC_JPY", "timestamp"=>"2017-11-12T10:24:38.877", "tick_id"=>7018190, "best_bid"=>712229.0, "best_ask"=>712230.0, "best_bid_size"=>0.1, "best_ask_size"=>1.1064, "total_bid_depth"=>7971.4496223, "total_ask_depth"=>7000.32085083, "ltp"=>712230.0, "volume"=>548669.0856824, "volume_by_product"=>490320.24070602}
  def get_ticker
    @uri.path = '/v1/getticker'
    @uri.query = 'product_code=FX_BTC_JPY'
    response = @https.get @uri.request_uri
    JSON.parse(response.body)
  end

  # return array of completed trade history(not my trade)
  def get_trade_hisotory
    @uri.path = '/v1/getexecutions'
    @uri.query = 'product_code=FX_BTC_JPY' #$before=x#after=y#count=zの価格指定可能
    response = @https.get @uri.request_uri
    JSON.parse(response.body)
  end

  # return array of completed my trade history
  # {"id"=>65860248, "side"=>"SELL", "price"=>863040.0, "size"=>0.0048, "exec_date"=>"2017-11-05T16:39:54.483", "child_order_id"=>"JOR20171105-163954-456414", "commission"=>7.2e-06, "child_order_acceptance_id"=>"JRF20171105-163953-183723"}
  def get_completed_order_history
    @uri.path = "/v1/me/getexecutions"
    @uri.query = "product_code=FX_BTC_JPY"
    options = get_option("GET")
    response = @https.request(options)
    JSON.parse(response.body)
  end

  # collateral: 預け入れた証拠金の評価額（円)
  # open_position_pnl: 建玉の評価損益（円）
  # require_collateral: 現在の必要証拠金（円）
  # keep_rate: 現在の証拠金維持率
  # {"collateral"=>5579.0, "open_position_pnl"=>0.0, "require_collateral"=>0.0, "keep_rate"=>0.0}
  def get_collateral
    @uri.path = "/v1/me/getcollateral"
    options = get_option("GET")
    response = @https.request(options)
    JSON.parse(response.body)
  end

  # this reture array of hash
  # [{"currency_code"=>"JPY", "amount"=>5579.0}, {"currency_code"=>"BTC", "amount"=>0.0}]
  def get_collateral_account
    @uri.path = "/v1/me/getcollateralaccounts"
    options = get_option("GET")
    response = @https.request(options)
    JSON.parse(response.body)
  end

  def initial_trade
    positions = get_position
    if positions == []
      initial_id = initial_trade_from_console
      order_id = confirm_order(initial_id)
    end
  end

  def confirm_order(order_id)
    p "Just making sure if the order is completed"
    loop do
      sleep(2)
      open_order = get_open_child_order
      position_check = get_position
      # last_trade = test.get_child_order_detail(order_id["child_order_acceptance_id"])
      # p open_order
      if open_order.empty?
        puts "REQUESTED ORDER IS COMPLETED"
        break
      else
        open_order_num = 0
        open_order.each do |order|
          open_order_num += 1
          # p open_order_num
          cancel_order(order["child_order_acceptance_id"], "child")
        end
        sleep(2)
        cancel_check = get_open_child_order
        position_check = get_position
        # p "This is open orders"
        # p cancel_check
        # p "This is positions"
        # p position_check
        if cancel_check.empty? && position_check.count < 2
          order_id = reorder_after_cancel(open_order[0])
          # puts "REORDERING"
          # p order_id
        end
      end
    end
    # p order_id
    order_id
  end

  # return order id
  # {"child_order_acceptance_id": "JRF20150707-050237-639234"}
  def initial_trade_from_console
    puts "Select order type \'MARKET\' or \'LIMIT\' "
    puts "1. BUY with hightest bid 2. SELL with lowest ask 3. LIMIT BUY 4. LIMIT SELL 5. MARKET BUY 6. MARKET SELL"
    order_num = gets
    if order_num.chomp == "1"
      ticker = get_ticker
      price = ticker["best_bid"].to_i + 1
      order_child("LIMIT", "BUY", @size, price)
    elsif order_num.chomp == "2"
      ticker = get_ticker
      price = ticker["best_ask"].to_i - 1
      order_child("LIMIT", "SELL", @size, price)
    elsif order_num.chomp == "3"
      puts "select order price"
      price = gets
      order_child("LIMIT", "BUY", @size, price.chomp)
    elsif order_num.chomp == "4"
      puts "select order price"
      price = gets
      order_child("LIMIT", "SELL", @size, price.chomp)
    elsif order_num.chomp == "5"
      order_child("MARKET", "BUY", @size)
    elsif order_num.chomp == "6"
      order_child("MARKET", "SELL", @size)
    end
  end

  def reorder_after_cancel(last_trade)
    side = last_trade["side"]
    order_type = last_trade["child_order_type"]
    size = last_trade["size"]
    ticker = get_ticker
    if side == "BUY"
      price = ticker["best_bid"].to_i + 1
    elsif side == "SELL"
      price = ticker["best_ask"].to_i - 1
    end
    order_child(order_type, side, size, price)
  end

  # return order id
  # {"child_order_acceptance_id": "JRF20150707-050237-639234"}
  def order_child(order_type, buy_sell, size, price = nil)
    if order_type == "LIMIT"
      body = '{
      "product_code" : "FX_BTC_JPY",
      "child_order_type" : "' + order_type + '",
      "side" : "' + buy_sell + '",
      "price" : "' + price.to_s + '",
      "size" : "' + size.to_s + '",
      "minute_to_expire" : 10000,
      "time_in_force" : "GTC"
      }'
    elsif order_type == "MARKET"
      body = '{
      "product_code" : "FX_BTC_JPY",
      "child_order_type" : "' + order_type + '",
      "side" : "' + buy_sell + '",
      "size" : "' + size.to_s + '",
      "minute_to_expire" : 10000,
      "time_in_force" : "GTC"
      }'
    end
    @uri.path = "/v1/me/sendchildorder"
    options = get_option("POST", body)
    options["Content-Type"] = "application/json"
    options.body = body
    # puts options.body
    response = @https.request(options)
    JSON.parse(response.body)
  end

  def cancel_order(acceptance_id, child_parent)
    # puts "CANCELING ORDER"
    @uri.path = "/v1/me/cancelchildorder"
    body = '{
      "product_code" : "FX_BTC_JPY",
      "' + child_parent + '_order_acceptance_id": "' + acceptance_id + '"
    }'
    options = get_option("POST", body)
    options["Content-Type"] = "application/json"
    options.body = body
    # puts JSON.parse(options.body)
    response = @https.request(options)
    # p response.body
    # JSON.parse(response.body)
  end

  # return {"parent_order_acceptance_id": "JRF20150707-050237-639234"}
  def order_parent(confirm_profit, stop_price, child_order_type, child_amount)
    @uri.path = "/v1/me/sendparentorder"
    if child_order_type == "BUY"
      side = "SELL"
    elsif child_order_type == "SELL"
      side = "BUY"
    end
    body = '{
      "order_method": "OCO",
      "minute_to_expire": 10000,
      "time_in_force": "GTC",
      "parameters": [
        {
          "product_code": "FX_BTC_JPY",
          "condition_type": "LIMIT",
          "side": "'+ side +'",
          "price": "'+ confirm_profit.to_s + '",
          "size": "'+ child_amount.to_s + '"
        },
        {
          "product_code": "FX_BTC_JPY",
          "condition_type": "STOP",
          "side": "'+ side +'",
          "trigger_price": "' + stop_price.to_s + '",
          "size": "' + child_amount.to_s + '"
        }
      ]
    }'
    options = get_option("POST", body)
    options["Content-Type"] = "application/json"
    options.body = body
    # puts JSON.parse(options.body)
    # response = @https.request(options)
    # JSON.parse(response.body)
  end

  def get_open_child_order
    @uri.path = "/v1/me/getchildorders"
    @uri.query = "product_code=FX_BTC_JPY&child_order_state=ACTIVE"
    options = get_option("GET")
    response = @https.request(options)
    JSON.parse(response.body)
  end

  # return {"id"=>153629006, "child_order_id"=>"JFX20171111-121234-379120F", "product_code"=>"FX_BTC_JPY", "side"=>"BUY", "child_order_type"=>"MARKET", "price"=>0.0, "average_price"=>737700.0, "size"=>0.1, "child_order_state"=>"COMPLETED", "expire_date"=>"2017-12-11T12:12:33", "child_order_date"=>"2017-11-11T12:12:33", "child_order_acceptance_id"=>"JRF20171111-211227-100096", "outstanding_size"=>0.0, "cancel_size"=>0.0, "executed_size"=>0.1, "total_commission"=>0.0}
  def get_child_order_detail(child__order_acceptance_id)
    @uri.path = "/v1/me/getchildorders"
    @uri.query = "product_code=FX_BTC_JPY&child_order_acceptance_id=" + child__order_acceptance_id
    options = get_option("GET")
    response = @https.request(options)
    JSON.parse(response.body)[0]
  end

  def confirm_profit_loss_cut
    puts "Waiting to confirm profit or loss cut"
    reorder_id = nil
    loop do
      sleep(1)
      positions = get_position
      collateral = get_collateral
      break if positions.empty?
      positions.each do |position|
      # p position
      begin
        if position["size"].to_f < 0.001
          p "Remove collateral which is less than 0.001" 
          size = position["size"].to_f + @size
          ticker = get_ticker
          if position["pnl"].to_f > 0
            if position["side"] == "BUY"
              price = ticker["best_bid"].to_i + 1
              order_id = order_child("LIMIT", "BUY", size, price)
            elsif position["side"] == "SELL"
              price = ticker["best_ask"].to_i - 1
              order_id = order_child("LIMIT", "SELL", size, price)
            end
            reorder_id = confirm_order(order_id)
          elsif position["pnl"].to_f < 0
            if position["side"] == "BUY"
              price = ticker["best_ask"].to_i - 1
              order_id = order_child("LIMIT", "SELL", size, price)
            elsif position["side"] == "SELL"
              price = ticker["best_bid"].to_i + 1
              order_id = order_child("LIMIT", "BUY", size, price)
            end
            reorder_id = confirm_order(order_id)
          end
        elsif position['pnl'].to_f >= position['size'].to_f * @confirm_line
          puts "------CONFIRM PROFIT---------"
          puts "SIDE: #{position["side"]}" 
          puts "SIZE: #{position["size"]}"
          puts "PROFIT: #{position["pnl"]}"
          puts "-----------------------------"
          child_side = position["side"]
          size = position["size"]
          ticker = get_ticker
          if child_side == "BUY"
            side = "SELL"
            price = ticker["best_ask"].to_i - 1
          elsif child_side == "SELL"
            side = "BUY"
            price = ticker["best_bid"].to_i + 1
          end
          order_id = order_child("LIMIT", side, size, price)
          reorder_id = confirm_order(order_id)
          reorder_id["profit_loss"] = "profit"
        elsif position['pnl'].to_f <= position['size'].to_f * @loss_cut_line
          puts "---------LOSS CUT------------"
          puts "SIDE: #{position["side"]}" 
          puts "SIZE: #{position["size"]}"
          puts "LOSS: #{position["pnl"]}"
          puts "-----------------------------"
          child_side = position["side"]
          size = position["size"]
          ticker = get_ticker
          if child_side == "BUY"
            side = "SELL"
            price = ticker["best_ask"].to_i - 1
          elsif child_side == "SELL"
            side = "BUY"
            price = ticker["best_bid"].to_i + 1
          end
            # 損が大きい場合は、成り行きで強制カット
            if position['pnl'].to_f <= position['size'].to_f * @loss_cut_line * 1.5
              puts "WANING: This is force loss cut"
              order_id = order_child("MARKET", side, size)
              sleep(2)
              reorder_id = confirm_order(order_id)
            else
              order_id = order_child("LIMIT", side, size, price)
              reorder_id = confirm_order(order_id)
            end
          reorder_id["profit_loss"] = "loss"
        end
      rescue TypeError
        p = "not sure why this happening"
      end
      end
    end
    reorder_id
  end

  # {"id"=>154620908, "child_order_id"=>"JFX20171112-155917-976905F", "product_code"=>"FX_BTC_JPY", "side"=>"SELL", "child_order_type"=>"LIMIT", "price"=>719999.0, "average_price"=>720000.0, "size"=>0.001, "child_order_state"=>"COMPLETED", "expire_date"=>"2017-11-19T14:39:16", "child_order_date"=>"2017-11-12T15:59:16", "child_order_acceptance_id"=>"JRF20171112-155916-553998", "outstanding_size"=>0.0, "cancel_size"=>0.0, "executed_size"=>0.001, "total_commission"=>0.0}
  def after_confirm_profit_loss_cut(confirmed_info)
    puts "START NEW TRADE"
    # p confirmed_info["child_order_acceptance_id"]
    # p confirmed_info
    positions = get_position
    # p positions
    if !positions.empty?
      puts "There should not be any position here"
    end
    begin 
      last_order = get_child_order_detail(confirmed_info["child_order_acceptance_id"])
    rescue
      last_order = get_completed_order_history[0]
    end
    loop do
      begin
      if confirmed_info["profit_loss"] == "loss"
        child_side = last_order["side"]
        # size = last_order["size"]
        ticker = get_ticker
        if child_side == "BUY"
          price = ticker["best_ask"].to_i - 1
        elsif child_side == "SELL"
          price = ticker["best_bid"].to_i + 1
        end
        order_id = order_child("LIMIT", child_side, @size, price)
        reorder_id = confirm_order(order_id)
        break
      elsif confirmed_info["profit_loss"] == "profit"
        child_side = last_order["side"]
        # size = last_order["size"]
        ticker = get_ticker
        if child_side == "BUY"
          side = "SELL"
          price = ticker["best_ask"].to_i - 1
        elsif child_side == "SELL"
          side = "BUY"
          price = ticker["best_bid"].to_i + 1
        end
        order_id = order_child("LIMIT", side, @size, price)
        reorder_id = confirm_order(order_id)
        break
      end
      rescue
        sleep(30)
        open_orders = get_open_child_order
        positions = get_position
        if !positions.empty?
          break
        elsif !open_orders.empty?
          open_orders[0].each do |k,v|
            if k == "child_order_acceptance_id"
              temp = {}
              temp[k] = v
              # p temp
              confirm_order(temp)
            end
          end
        else
          ticker = get_ticker

          side = rand(1)
          if side == 0
            price = ticker["best_ask"].to_i - 1
            order_id = order_child("LIMIT", "SELL", @size, price)
          elsif side == 1
            price = ticker["best_bid"].to_i + 1
            order_id = order_child("LIMIT", "BUY", @size, price)
          end
          confirm_order(order_id)
          break
        end
      end
    end
  end

  def get_position
    @uri.path = "/v1/me/getpositions"
    @uri.query = "product_code=FX_BTC_JPY"
    options = get_option("GET")
    response = @https.request(options)
    JSON.parse(response.body)  
  end

  private
  def get_option(get_or_post, body = nil)
    timestamp = Time.now.to_i.to_s
    method = get_or_post
    if body.nil?
      text = timestamp + method + @uri.request_uri
    else
      text = timestamp + method + @uri.request_uri + body
    end
    sign = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), @secret, text)
    if method == "GET"
      options = Net::HTTP::Get.new(@uri.request_uri, initheader = {
        "ACCESS-KEY" => @key,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
      });
    elsif method == "POST"
      options = Net::HTTP::Post.new(@uri.request_uri, initheader = {
        "ACCESS-KEY" => @key,
        "ACCESS-TIMESTAMP" => timestamp,
        "ACCESS-SIGN" => sign,
      });
    end
  end
end

# def trade
#   if !ENV['SIZE'].nil?
#     size = ENV['SIZE']
#     confirm_line = ENV['CONFIRM_LINE']
#     loss_cut_line = ENV['LOSS_CUT_LINE']
#   else
#     if ARGV.count == 0
#       puts "Select order volume"
#       size = gets
#       puts "Puts confirm line"
#       confirm_line = gets
#       puts "Puts loss cut line"
#       loss_cut_line = gets
#     elsif ARGV.count == 3
#       size = ARGV[0]
#       puts size
#       confirm_line = ARGV[1]
#       puts confirm_line
#       loss_cut_line = ARGV[2]
#       puts loss_cut_line
#     else
#       puts "Not enough args"
#       puts "SIZE, CONFIRM LINE and LOSS CUT LINE"
#     end
#   end
#   bitfly = BitFlyer.new(size, confirm_line, loss_cut_line)
#   # bitfly.initial_trade
#   loop do
#     reorder_id = bitfly.confirm_profit_loss_cut
#     # p reorder_id
#     bitfly.after_confirm_profit_loss_cut(reorder_id)
#   end
# end

# trade

# test = BitFlyer.new
# p test.get_position
# test.second_order
# test.order_parent(650000, 670000, )
# p test.get_all_child_order
# p test.get_completed_order_history[0]
# p test.get_collateral_account
# p order_id
# order_id = {"child_order_acceptance_id"=>"JRF20171112-100417-274010"}
# test.get_product_list

# test.order("MARKET", "BUY", 0.01)
# test.cancel_order("test","child")
# p test.order_parent("1","2","BUY","3")
# p test.get_ticker

# order_id = test.initial_trade_from_console
# p order_id
# loop do
#   sleep(3)
#   open_order = test.get_open_child_order
#   # last_trade = test.get_child_order_detail(order_id["child_order_acceptance_id"])
#   # p open_order
#   if open_order == []
#     p "order completed"
#     break
#   else
#     test.cancel_order(order_id["child_order_acceptance_id"], "child")
#     test.reorder_after_cancel(open_order[0])
#   end
# end