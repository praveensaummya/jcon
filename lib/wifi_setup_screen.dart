import 'package:flutter/material.dart';
import 'wifi_provisioning_service.dart';

class WifiSetupScreen extends StatefulWidget{
  const WifiSetupScreen({super.key});
  @override
  State<WifiSetupScreen> createState()=> _wifiSetupScreenState();
}
class _wifiSetupScreenState extends State<WifiSetupScreen>{
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final WifiProvisioningService _provisioningService = WifiProvisioningService();
  bool _isLoading = false;
  String _statusMessage = "";

  Future<void> _submitCredentials()async{
    setState(() {
      _isLoading = true;
      _statusMessage = "sending credentials to ESP32...";
    });
    bool success = await _provisioningService.sendWifiCredentials(
      _ssidController.text.trim(),
      _passwordController.text.trim(),
    );
    setState(() {
      _isLoading = false;
      if(success){
        _statusMessage = "success! ESP32 is now rebooting to connect";

      }else{
        _statusMessage = "Failed. Make sure you are connected to ESP32`s WI-FI hotspot";
      }
    });
  }
@override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 WI-FI Setup'),
        centerTitle: true,
      ),
    body: SafeArea(
      child: Center(
      child: SingleChildScrollView(
    
      padding: const EdgeInsets.all(24.0),
      child:Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.wifi,size: 80,color: Colors.blue),
          const SizedBox(height: 24,),
          const Text(
            "Connect your phone to the ESP32 hotspot,then enter your home WI-FI/Mobile  Hotspot details below",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox( height :32),
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText:'WI-FI Name(SSID)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.router),  
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
          ),
          const SizedBox(height: 24,),
          ElevatedButton(onPressed: _isLoading ? null :_submitCredentials,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16)
          ),
           child: _isLoading
           ?const CircularProgressIndicator(color: Colors.white,)
           :const Text('Send to ESP32',style:  TextStyle(fontSize: 18),
              )
           ),
          const SizedBox(height: 24,),
          Text(_statusMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _statusMessage.contains("success")? Colors.green : Colors.red,
            fontWeight: FontWeight.bold
          ),
          )
        ],
      ),
      ),
    ),
    )
    );
  } 
  
}