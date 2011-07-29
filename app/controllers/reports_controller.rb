class ReportsController < ApplicationController
  admin_tab     :all
  before_filter :authenticate_user!
  before_filter :check_acting_as
  before_filter :init_current_facility
  before_filter :init_report_params

  load_and_authorize_resource :class => ReportsController


  def initialize
    @active_tab = 'admin_reports'
    super
  end


  def index
    redirect_to product_facility_reports_path
  end


  def product
    render_general_report(0, 'Name') {|od| od.product.name }
  end


  def account
    render_general_report(1, 'Number') {|od| od.account.account_number }
  end


  def account_owner
    render_general_report(2, 'Name') do |od|
      owner=od.account.owner.user
      "#{owner.full_name} (#{owner.username})"
    end
  end


  def purchaser
    render_general_report(3, 'Name') do |od|
      usr=od.order.user
      "#{usr.full_name} (#{usr.username})"
    end
  end


  def price_group
    render_general_report(4, 'Name') {|od| od.price_policy ? od.price_policy.price_group.name : 'Unassigned' }
  end

  
  def instrument_utilization
    render_report_download 'instrument_utilization' do
      Reservation.where(%q/orders.facility_id = ? AND reserve_start_at >= ? AND reserve_start_at <= ? AND canceled_at IS NULL AND (order_details.state IS NULL OR order_details.state = 'complete')/, current_facility.id, @date_start, @date_end).
                 joins('LEFT JOIN order_details ON reservations.order_detail_id = order_details.id INNER JOIN orders ON order_details.order_id = orders.id').
                 includes(:order_detail, :account, :instrument).
                 order('reserve_start_at ASC')
    end
  end


  private

  def init_report_params
    os, status_id=nil, params[:status_filter]

    if status_id.blank?
      os=OrderStatus.complete.first
    elsif status_id.to_i != -1 # not all
      os=OrderStatus.find(status_id.to_i)
    end

    if os
      @selected_status_id=os.id
      @status_ids=(os.root? ? os.children.collect(&:id) : []).push(os.id)
    else
      @selected_status_id=-1
      @status_ids=OrderStatus.non_protected_statuses(current_facility).collect(&:id)
    end

    if params[:date_start].blank?
      now=Date.today
      @date_start=Date.new(now.year, now.month, 1) - 1.month
    else
      @date_start=parse_usa_date(params[:date_start])
    end
         
    if params[:date_start].blank?
      @date_end=@date_start + 42.days
      @date_end=Date.new(@date_end.year, @date_end.month) - 1.day
    else
      @date_end=parse_usa_date(params[:date_end])
    end
  end
  
  
  def init_report_headers(report_on_label)
    @headers=[ report_on_label, 'Quantity', 'Total Cost', 'Percent of Cost' ]
  end
  
  
  def init_general_report_data(report_on_label, &report_on)
    @report_on=report_on
    init_report_headers report_on_label
    @total_cost, @report_data=0.0, report_data.all       
    @report_data.each {|od| @total_cost += od.total }    
  end
  

  def init_general_report(report_on_label)
    sums, rows, @total_quantity, @total_cost={}, [], 0, 0.0
    init_report_headers report_on_label

    report_data.all.each do |od|
      key=yield od
      sums[key]=[0,0] unless sums.has_key?(key)
      sums[key][0] += od.quantity
      @total_quantity += od.quantity
      sums[key][1] += od.total
      @total_cost += od.total
    end

    sums.each do |k,v|
      frac_cost=@total_cost > 0 ? v[1] / @total_cost : 1
      rows << v.push(frac_cost * 100).unshift(k)
    end

    rows.sort! {|a,b| a.first <=> b.first}
    page_size=25
    page=params[:page].blank? || rows.size < page_size ? 1 : params[:page].to_i    
    #page=1 if (rows.size / page_size).to_i < page
        
    @rows=WillPaginate::Collection.create(page, page_size) do |pager|       
      pager.replace rows[ pager.offset, pager.per_page ]
      pager.total_entries=rows.size unless pager.total_entries
    end
  end


  def render_general_report(tab_index, report_on_label, &report_on)
    @selected_index=tab_index

    respond_to do |format|
      format.js do
        init_general_report(report_on_label, &report_on)
        render :action => 'general_report_table'
      end

      format.html { render :action => 'general_report' }

      format.csv do
        export_type=params[:export_id]             
        
        case export_type
          when nil, '' 
            raise 'Export type not found'
          when 'general_report'
            init_general_report(report_on_label, &report_on)
          when 'general_report_data'
            init_general_report_data(report_on_label, &report_on)
        end
        
        render_csv("#{action_name}_#{export_type}", export_type)
      end
    end
  end  


  def render_report_download(report_prefix)
    @reportables = yield

    respond_to do |format|
      format.html
      format.csv { render_csv(report_prefix) }
    end
  end


  def render_csv(filename = nil, action=nil)
    filename ||= params[:action]
    filename += "_#{@date_start.strftime("%Y%m%d")}-#{@date_end.strftime("%Y%m%d")}.csv"

    if request.env['HTTP_USER_AGENT'] =~ /msie/i
      headers['Pragma'] = 'public'
      headers["Content-type"] = "text/plain"
      headers['Cache-Control'] = 'no-cache, must-revalidate, post-check=0, pre-check=0'
      headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
      headers['Expires'] = "0"
    else
      headers["Content-Type"] ||= 'text/csv'
      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
    end

    render_with={ :layout => false}
    render_with.merge!(:action => action) if action
    render render_with
  end
  
  
  def report_data
    OrderDetail.joins(:order_status).
               where('order_statuses.id' => @status_ids).
               joins('LEFT JOIN orders ON order_details.order_id = orders.id').
               where('orders.facility_id = ? AND orders.ordered_at >= ? AND orders.ordered_at <= ?', current_facility.id, @date_start, @date_end).
               includes(:order, :account, :price_policy, :product)
  end
  
end
