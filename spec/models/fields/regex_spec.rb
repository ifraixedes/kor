require 'spec_helper'

describe Fields::Regex do
  
  it "should serialize it's settings" do
    kind = FactoryGirl.create(:works)
  
    field = described_class.create(
      :kind_id => kind.id,
      :name => 'trick_id',
      :show_label => 'Trick ID',
      :settings => {:regex => "^(aa|bb|ccc)$"}
    )
    
    expect(field.reload.settings).to eq({:regex => "^(aa|bb|ccc)$"})
  end
  
end
