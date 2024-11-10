require 'sinatra'
require 'openai'
require 'dotenv'

Dotenv.load

client     = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
show_input = false
ingredients = []
macros      = []
recipe_name = nil

get '/' do
  erb :index, locals: { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }
end

post '/toggle_div' do
  show_input = !show_input

  erb :index, locals: { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }
end

post '/remove' do
  ingredients = []
  macros      = []
  recipe_name = nil

  erb :index, locals: { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }
end

post '/ask' do
  recipe_name = params[:recipe_name]
  show_input  = !show_input

  if recipe_name.nil? || recipe_name.strip.empty?
    @error = "Please enter a valid recipe name."

    recipe_name = nil
    return erb :index, { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }
  end

  begin
    response = client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { 
            role: 'user', 
            content: <<~PROMPT
              Give me a list of ingredients for a #{recipe_name} recipe. 
              If this is not a recipe, don't provide anything.
              For each ingredient, include the name of the food and a precise quantity. 
              Avoid using vague terms like 'to taste,' 'as needed,' or similar. 
              Each ingredient must have a clear and measurable quantity.
              The quantity must be for only one person.
              Use only grams for the quantity, don't give any other info, just grams.
              To separate the name of the food and the quantity, use a "-"
              The name of the food, should be the one used on the USDA DB.
              Up to 7 ingredients. Only provide foods who are strictly necessary for the recipe.
              It shall follow this structure: Food Name - 50g\nOther food name: 300 grams
              Finally, provide the total number of energy in kcal, fat in g, Carbohydrate in g, and protein in g of this recipe.
              It shall follow this structure: Energy: X kcal\nFat: X grams\nCarbohydrates: X grams\nProtein: X grams
              To separate the name of the macros and the quantity, use a ":"
            PROMPT
          }
        ]
      }
    )
    
    puts "Raw response: #{response}"
    info = response.dig('choices', 0, 'message', 'content')

    if info
      ingredients, macros = process_info(info)
    end

    puts "Ingredients: #{ingredients}, Macros: #{macros}"
    if ingredients.to_a.empty? && macros.to_a.empty?
      recipe_name = nil
      show_input = true

      @error = "We were not able to process your request. Please try again."
    end

    erb :index, locals: { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }
  rescue OpenAI::Error => e
    @error = "An error occurred while contacting OpenAI: #{e.message}"
    erb :index, locals: { recipe_name: recipe_name, show_input: show_input, ingredients: ingredients, macros: macros }
  end
end

def process_info(info)
  meal_info = info.split("\n").reject(&:empty?)
  macros = []

  return [] if meal_info.length < 2

  structured_ingredients = meal_info.map do |ingredient|
    ingredient = ingredient.strip
    ingredient = ingredient.sub(/^\d+\.\s*/, '')

    parts = ingredient.split(" - ", 2)

    if invalid_duo?(parts)
      parts = ingredient.split(":", 2)
      
      next if invalid_duo?(parts)

      macro_name = parts[0].strip
      macro_quantity = parts[1].strip

      macros << { quantity: macro_quantity, name: macro_name }

      next
    end
    
    name = parts[0].strip
    quantity = parts[1].strip

    if quantity.downcase.include?("to taste") || quantity.downcase.include?("as needed")
      next
    end

    { quantity: quantity, name: name }
  end
  
  [structured_ingredients.compact, macros.compact]
end

def invalid_duo?(parts)
  parts.length < 2 || parts[0].empty? || parts[1].empty?
end