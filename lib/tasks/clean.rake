namespace :clean do

  task :type, [:type] =>  [:environment] do |t, args|
    puts "Removign all items of type [#{args[:type]}]"

    klass = Kernel.const_get(args[:type]).all.each do |item|
    # puts klass
    # puts eval(args[:type])
    # klass.each do |item|
      item.destroy
    end
  end
end
