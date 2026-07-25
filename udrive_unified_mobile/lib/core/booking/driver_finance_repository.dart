import '../network/api_client.dart';
class DriverFinanceRepository { DriverFinanceRepository(this._api); final ApiClient _api;
Future<Map<String,dynamic>> load(){return _api.getJson('/api/v1/driver/finance').then((v)=>Map<String,dynamic>.from(v['data'] as Map));}
Future<void> requestPayout({required double amount,required String method,String? destination,required int version}) async {await _api.postJson('/api/v1/driver/finance/payouts',{'amount':amount,'payoutMethod':method,'destinationMasked':destination,'notes':'Requested from Driver app','expectedWalletVersion':version});}}
