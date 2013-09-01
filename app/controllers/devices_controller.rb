class DevicesController < ApplicationController
  require 'net/http'
  require 'json'

  def flatten_params(params, prefix = nil)
    output = []
    for n, v in params
      next if n.start_with?('_')
      if v.include?('_value')
        v['_path'] = "#{prefix}#{n}"
        v['_type'] = v['_value'].class
        output << v
      elsif v['_object'] == true or v['_instance'] == true
        v['_path'] = "#{prefix}#{n}"
        output << v
        output += flatten_params(v, prefix ? "#{prefix}#{n}." : "#{n}.")
      end
    end
    return output
  end

  def get_device(id)
    query = {
      'query' => ActiveSupport::JSON.encode({'_id' => URI.escape(id)}),
    }
    http = Net::HTTP.new(Rails.configuration.genieacs_api_host, Rails.configuration.genieacs_api_port)
    res = http.get("/devices/?#{query.to_query}")
    @now = res['Date'].to_time
    return ActiveSupport::JSON.decode(res.body)[0]
  end

  def find_devices(query, skip = 0, limit = 10, sort = nil)
    q = {
      'query' => ActiveSupport::JSON.encode(query),
      'skip' => skip,
      'limit' => limit,
      'projection' => 'summary',
    }
    q['sort'] = ActiveSupport::JSON.encode(sort) if sort
    http = Net::HTTP.new(Rails.configuration.genieacs_api_host, Rails.configuration.genieacs_api_port)
    res = http.get("/devices/?#{q.to_query}")
    @total = res['Total'].to_i
    @now = res['Date'].to_time
    return ActiveSupport::JSON.decode(res.body)
  end

  def index
    skip = params.include?(:page) ? (Integer(params[:page]) - 1) * 30 : 0
    if params.include?(:sort)
      sort_param = params[:sort].start_with?('-') ? params[:sort][1..-1] : params[:sort]
      sort_dir = params[:sort].start_with?('-') ? -1 : 1
      sort = {sort_param => sort_dir}
    else
      sort = nil
    end

    @query = {}
    if params.has_key?('query')
      @query = ActiveSupport::JSON.decode(URI.unescape(params['query']))
    end
    if request.format == Mime::CSV
      @devices = find_devices(@query, 0, 0)
    else
      @devices = find_devices(@query, skip, 30, sort)
    end

    respond_to do |format|
      format.html # index.html.erb
      format.csv
      format.json { render json: @devices }
    end
  end

  # GET /devices/1
  # GET /devices/1.json
  def show
    @device = get_device(params[:id])
    @device_params = flatten_params(@device['InternetGatewayDevice'])
    @files = FilesController.find_files({})
    mac = @device['summary.mac']['_value'].gsub(':', '') rescue nil
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @device }
    end
  end

  def update
    if params.include? 'refresh_summary'
      task = {'name' => 'getParameterValues', 'parameterNames' => ['summary']}
      http = Net::HTTP.new(Rails.configuration.genieacs_api_host, Rails.configuration.genieacs_api_port)
      res = http.post("/devices/#{URI.escape(params[:id])}/tasks?timeout=3000&connection_request", ActiveSupport::JSON.encode(task))

      if res.code == '200'
        flash[:success] = 'Device refreshed'
      elsif res.code == '202'
        flash[:warning] = 'Device is offline'
      else
        flash[:error] = "Unexpected error (#{res.code})"
      end
    end

    if params.include? 'add_tag'
      tag = ActiveSupport::JSON.decode(params['add_tag']).strip
      http = Net::HTTP.new(Rails.configuration.genieacs_api_host, Rails.configuration.genieacs_api_port)
      res = http.post("/devices/#{URI.escape(params[:id])}/tags/#{tag}", nil)

      if res.code == '200'
        flash[:success] = 'Tag added'
      else
        flash[:error] = "Unexpected error (#{res.code})"
      end
    end

    if params.include? 'remove_tag'
      tag = ActiveSupport::JSON.decode(params['remove_tag']).strip
      http = Net::HTTP.new(Rails.configuration.genieacs_api_host, Rails.configuration.genieacs_api_port)
      res = http.delete("/devices/#{URI.escape(params[:id])}/tags/#{tag}", nil)

      if res.code == '200'
        flash[:success] = 'Tag removed'
      else
        flash[:error] = "Unexpected error (#{res.code})"
      end
    end

    if params.include? 'commit'
      tasks = ActiveSupport::JSON.decode(params['commit'])
      http = Net::HTTP.new(Rails.configuration.genieacs_api_host, Rails.configuration.genieacs_api_port)

      for t in tasks
        res = http.post("/devices/#{URI.escape(params[:id])}/tasks?timeout=3000&connection_request", ActiveSupport::JSON.encode(t))
        if res.code == '200'
          flash[:success] = 'Tasks committed'
        elsif res.code == '202'
          flash[:warning] = 'Tasks added to queue and will be committed when device is online'
        else
          flash[:error] = "Unexpected error (#{res.code})"
        end
      end
    end

    #redirect_to :action => :show
    redirect_to "/devices/#{URI.escape(params[:id])}"
  end

end
