require 'rails_helper'

RSpec.describe Member, type: :model do
  describe 'luck history' do
    it 'adds a luck history model when luck is updated' do
      m = Member.create! telegram_user: 1234, username: 'test'

      expect(m.luck).to eq 50
      expect(m.luck_histories.size).to eq 0

      m.update_luck 20
      m.reload

      expect(m.luck).to eq 20
      expect(m.luck_histories.size).to eq 1
      expect(m.luck_histories.first.luck).to eq 20

      m.update_luck 100
      m.reload

      expect(m.luck).to eq 100
      expect(m.luck_histories.size).to eq 2
      expect(m.luck_histories.order(:created_at).first.luck).to eq 20
      expect(m.luck_histories.order(:created_at).second.luck).to eq 100
    end
  end

  describe 'display name' do
    it 'uses first and last name' do
      u = Member.new first_name: 'Firstname', last_name: 'Lastname'
      expect(u.display_name).to eq('Firstname Lastname')
    end

    it 'uses first name' do
      u = Member.new first_name: 'Firstname'
      expect(u.display_name).to eq('Firstname')
    end

    it 'favors full name over username' do
      u = Member.new first_name: 'Firstname', last_name: 'Lastname', username: 'auser'
      expect(u.display_name).to eq('Firstname Lastname')
    end

    it 'falls back to username' do
      u = Member.new username: 'auser'
      expect(u.display_name).to eq('auser')
    end

    it 'bolds names' do
      u = Member.new first_name: 'Firstname', last_name: 'Lastname', username: 'auser'
      expect(u.display_name(true)).to eq('<b>Firstname Lastname</b>')
    end
  end
end
