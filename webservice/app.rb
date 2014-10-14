########
# app.rb
#

require 'sinatra/base'
require "sinatra/reloader"

class XbmApp < Sinatra::Base
  WIDTH  = 264
  HEIGHT = 176

  configure :development do
    register Sinatra::Reloader
  end

  set :root, File.dirname(__FILE__)

  get '/' do
    'OK'
  end

  post '/:agent/image.?:format?' do
    agent = params[:agent]
    format = params[:format] || 'png'

    image = Magick::Image.read(params['file'][:tempfile].path) do
      self.background_color = 'white'
      self.antialias = false
    end.first

    image.colorspace = Magick::GRAYColorspace
    image.image_type = Magick::BilevelType

    image = image.resize_to_fit(WIDTH, HEIGHT).extent(WIDTH, HEIGHT)

    send_image(image, agent)
    if format == 'txt'
      interlace(pixels).unpack("H*").to_s
    else
      #Give the user the png version
      content_type 'image/png'
      image.format = 'png'
      image.to_blob
    end

  end

  get '/:agent/text.?:format?' do
    #agent url, text
    msg = params[:msg] || 'hello world'
    agent = params[:agent]
    format = params[:format] || 'png'
    text = Magick::Draw.new

    image = Magick::Image.new(WIDTH, HEIGHT) do
      self.colorspace = Magick::GRAYColorspace
      self.image_type = Magick::BilevelType
      self.background_color = 'white'
      self.antialias = false
    end

    text.annotate(image, WIDTH, HEIGHT, 0, 0, msg) do
      self.pointsize = 36
      self.font = "Helvetica"
      self.font_weight = Magick::BoldWeight
      self.gravity = Magick::CenterGravity
      self.fill = 'black'
    end

    send_image(image, agent)
    if format == 'txt'
      interlace(pixels).unpack("H*").to_s
    else
      #Give the user the png version
      content_type 'image/png'
      image.format = 'png'
      image.to_blob
    end
  end

  def send_image(image, agent)
    agent_url = "https://agent.electricimp.com/#{agent}/image"
    pixels = image.rotate(180).negate.export_pixels(0, 0, WIDTH, HEIGHT, 'I')

    options = {
      :body => interlace(pixels)
    }

    HTTParty.post(agent_url, options)
  end

  def interlace(pixels)
    [pixels.collect{|p| [1, p].min}.join].pack("B*")
  end

end
