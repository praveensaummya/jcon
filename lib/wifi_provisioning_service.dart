import 'dart:convert';
import 'package:http/http.dart' as http;
class WifiProvisioningService {

  final String apIpAddress = "10.10.0.1";
  Future<bool> sendWifiCredentials(String ssid,String password)async{
    try{
      final response = await http.post(Uri.parse('http://$apIpAddress/connect.json'),
      headers: {
        "Content-Type":"application/json",
        "X-Custom-ssid":ssid,
        "X-Custom-pwd" :password,
      },
      body: jsonEncode({"timestamp":DateTime.now().millisecondsSinceEpoch}),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    }catch(e){
      print("AP Provisioning Error: $e");
      return false;
    }
  }
}