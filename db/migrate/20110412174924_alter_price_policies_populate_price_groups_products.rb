class AlterPricePoliciesPopulatePriceGroupsProducts < ActiveRecord::Migration
  def self.up
    PricePolicy.all.each do |policy|
      next if policy.restrict_purchase?

      attrs={ :price_group => policy.price_group }

      if policy.is_a? ItemPricePolicy
        attrs.merge!(:product => policy.item)
      elsif policy.is_a? ServicePricePolicy
        attrs.merge!(:product => policy.service)
      elsif policy.is_a? InstrumentPricePolicy
        attrs.merge!(:product => policy.instrument)
        attrs.merge!(:reservation_window => policy[:reservation_window])
      end

      PriceGroupProduct.create!(attrs)
    end

    remove_column(:price_policies, :reservation_window)
    remove_column(:price_policies, :restrict_purchase)
  end


  def self.down
    #add_column(:price_policies, :reservation_window, :integer)
    #add_column(:price_policies, :restrict_purchase, :boolean)
    PricePolicy.reset_column_information

    PricePolicy.all.each do |policy|
      product=case policy
                when ItemPricePolicy then policy.item
                when ServicePricePolicy then policy.service
                when InstrumentPricePolicy then policy.instrument
              end

      pgp=PriceGroupProduct.find_by_price_group_id_and_product_id(policy.price_group.id, product.id)

      policy.restrict_purchase=pgp.nil?
      policy.reservation_window=pgp.reservation_window if pgp and product.is_a? Instrument
      policy.save!

      pgp.destroy if pgp
    end        
  end
end
