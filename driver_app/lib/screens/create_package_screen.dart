import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/app_theme.dart';
class CreatePackageScreen extends StatefulWidget { const CreatePackageScreen({super.key}); @override State<CreatePackageScreen> createState()=>_CreatePackageScreenState(); }
class _CreatePackageScreenState extends State<CreatePackageScreen> {
  final key=GlobalKey<FormState>(); final title=TextEditingController(); final route=TextEditingController(); final price=TextEditingController(); final itinerary=TextEditingController();
  int days=3; bool customerOffers=true; bool fuel=true; bool tolls=true; bool hotel=false;
  @override void dispose(){title.dispose();route.dispose();price.dispose();itinerary.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(DS.of(context,'createPackage'))),body:Form(key:key,child:ListView(padding:const EdgeInsets.fromLTRB(18,8,18,30),children:[
    Container(height:160,decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(colors:[AppColors.primary,AppColors.secondary])),child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.add_a_photo_outlined,color:Colors.white,size:44),SizedBox(height:8),Text('Add package cover image',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w800))])),
    const SizedBox(height:16),TextFormField(controller:title,decoration:const InputDecoration(labelText:'Package title'),validator:_required),const SizedBox(height:12),
    TextFormField(controller:route,decoration:const InputDecoration(labelText:'Route and destinations'),validator:_required),const SizedBox(height:12),
    DropdownButtonFormField<int>(value:days,decoration:const InputDecoration(labelText:'Duration'),items:List.generate(10,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1} day${i==0?'':'s'}'))),onChanged:(v)=>setState(()=>days=v??3)),const SizedBox(height:12),
    TextFormField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Package price',prefixText:'PKR '),validator:_required),const SizedBox(height:12),
    TextFormField(controller:itinerary,maxLines:5,decoration:const InputDecoration(labelText:'Day-by-day itinerary',alignLabelWithHint:true),validator:_required),const SizedBox(height:16),
    Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Allow customer price offers',style:TextStyle(fontWeight:FontWeight.w800)),value:customerOffers,onChanged:(v)=>setState(()=>customerOffers=v)),const Divider(),CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Fuel included'),value:fuel,onChanged:(v)=>setState(()=>fuel=v??false)),CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Tolls included'),value:tolls,onChanged:(v)=>setState(()=>tolls=v??false)),CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Hotel included'),value:hotel,onChanged:(v)=>setState(()=>hotel=v??false))]))),
    const SizedBox(height:18),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>_done(context,'Package saved as draft'),child:Text(DS.of(context,'saveDraft')))),const SizedBox(width:10),Expanded(child:FilledButton(onPressed:(){if(key.currentState!.validate())_done(context,'Package submitted for approval');},child:Text(DS.of(context,'submitApproval'))))]),
  ])));
  static String? _required(String? v)=>v==null||v.trim().isEmpty?'Required':null;
  void _done(BuildContext context,String text){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));Navigator.pop(context);}
}
