///File download from FlutterViz- Drag and drop a tools. For more details visit https://flutterviz.io/

import 'package:flutter/material.dart';


class SSKSettings extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xffffffff),
      appBar:
      AppBar(
        elevation:0,
        centerTitle:true,
        automaticallyImplyLeading: false,
        backgroundColor:Color(0xffff0004),
        shape:RoundedRectangleBorder(
          borderRadius:BorderRadius.zero,
        ),
        title:Text(
          "SmartSpin2k",
          style:TextStyle(
            fontWeight:FontWeight.w500,
            fontStyle:FontStyle.normal,
            fontSize:14,
            color:Color(0xffffffff),
          ),
        ),
        leading: Icon(
          Icons.arrow_back,
          color:Color(0xffffffff),
          size:24,
        ),
      ),
      body:Padding(
        padding:EdgeInsets.symmetric(vertical: 0,horizontal:16),
        child:SingleChildScrollView(
          child:
          Column(
            mainAxisAlignment:MainAxisAlignment.start,
            crossAxisAlignment:CrossAxisAlignment.start,
            mainAxisSize:MainAxisSize.max,
            children: [

              ListView(
                scrollDirection: Axis.vertical,
                padding:EdgeInsets.all(0),
                shrinkWrap:true,
                physics:ScrollPhysics(),
                children:[


                  Card(
                    margin:EdgeInsets.fromLTRB(0, 0, 0, 16),
                    color:Color(0xffffffff),
                    shadowColor:Color(0x4d939393),
                    elevation:1,
                    shape:RoundedRectangleBorder(
                      borderRadius:BorderRadius.circular(4.0),
                      side: BorderSide(color:Color(0x4d9e9e9e), width:1),
                    ),
                    child:
                    Padding(
                      padding:EdgeInsets.all(16),
                      child:Row(
                        mainAxisAlignment:MainAxisAlignment.start,
                        crossAxisAlignment:CrossAxisAlignment.center,
                        mainAxisSize:MainAxisSize.max,
                        children:[

                          Expanded(
                            flex: 1,
                            child: Padding(
                              padding:EdgeInsets.symmetric(vertical: 0,horizontal:16),
                              child:
                              Column(
                                mainAxisAlignment:MainAxisAlignment.start,
                                crossAxisAlignment:CrossAxisAlignment.start,
                                mainAxisSize:MainAxisSize.max,
                                children: [
                                  Text(
                                    "Saved Power Meter",
                                    textAlign: TextAlign.start,
                                    maxLines:1,
                                    overflow:TextOverflow.clip,
                                    style:TextStyle(
                                      fontWeight:FontWeight.w700,
                                      fontStyle:FontStyle.normal,
                                      fontSize:16,
                                      color:Color(0xff000000),
                                    ),
                                  ),
                                  Padding(
                                    padding:EdgeInsets.fromLTRB(0, 4, 0, 0),
                                    child:Text(
                                      "Favero Assioma",
                                      textAlign: TextAlign.start,
                                      maxLines:1,
                                      overflow:TextOverflow.ellipsis,
                                      style:TextStyle(
                                        fontWeight:FontWeight.w400,
                                        fontStyle:FontStyle.normal,
                                        fontSize:14,
                                        color:Color(0xff6c6c6c),
                                      ),
                                    ),
                                  ),
                                ],),),),
                          Icon(
                            Icons.arrow_forward_ios,
                            color:Color(0xff212435),
                            size:24,
                          ),
                        ],),),
                  ),

                  Card(
                    margin:EdgeInsets.fromLTRB(0, 0, 0, 16),
                    color:Color(0xffffffff),
                    shadowColor:Color(0x4d939393),
                    elevation:1,
                    shape:RoundedRectangleBorder(
                      borderRadius:BorderRadius.circular(4.0),
                      side: BorderSide(color:Color(0x4d9e9e9e), width:1),
                    ),
                    child:
                    Padding(
                      padding:EdgeInsets.all(16),
                      child:Row(
                        mainAxisAlignment:MainAxisAlignment.start,
                        crossAxisAlignment:CrossAxisAlignment.center,
                        mainAxisSize:MainAxisSize.max,
                        children:[

                          Expanded(
                            flex: 1,
                            child: Padding(
                              padding:EdgeInsets.symmetric(vertical: 0,horizontal:16),
                              child:
                              Column(
                                mainAxisAlignment:MainAxisAlignment.start,
                                crossAxisAlignment:CrossAxisAlignment.start,
                                mainAxisSize:MainAxisSize.max,
                                children: [
                                  Text(
                                    "Saved HRM",
                                    textAlign: TextAlign.start,
                                    maxLines:1,
                                    overflow:TextOverflow.clip,
                                    style:TextStyle(
                                      fontWeight:FontWeight.w700,
                                      fontStyle:FontStyle.normal,
                                      fontSize:16,
                                      color:Color(0xff000000),
                                    ),
                                  ),
                                  Padding(
                                    padding:EdgeInsets.fromLTRB(0, 4, 0, 0),
                                    child:Text(
                                      "ab:cd:ef:gh",
                                      textAlign: TextAlign.start,
                                      maxLines:1,
                                      overflow:TextOverflow.ellipsis,
                                      style:TextStyle(
                                        fontWeight:FontWeight.w400,
                                        fontStyle:FontStyle.normal,
                                        fontSize:14,
                                        color:Color(0xff6c6c6c),
                                      ),
                                    ),
                                  ),
                                ],),),),
                          Icon(
                            Icons.arrow_forward_ios,
                            color:Color(0xff212435),
                            size:24,
                          ),
                        ],),),
                  ),

                  Card(
                    margin:EdgeInsets.fromLTRB(0, 0, 0, 16),
                    color:Color(0xffffffff),
                    shadowColor:Color(0x4d939393),
                    elevation:1,
                    shape:RoundedRectangleBorder(
                      borderRadius:BorderRadius.circular(4.0),
                      side: BorderSide(color:Color(0x4d9e9e9e), width:1),
                    ),
                    child:
                    Padding(
                      padding:EdgeInsets.all(16),
                      child:Row(
                        mainAxisAlignment:MainAxisAlignment.start,
                        crossAxisAlignment:CrossAxisAlignment.center,
                        mainAxisSize:MainAxisSize.max,
                        children:[

                          Expanded(
                            flex: 1,
                            child: Padding(
                              padding:EdgeInsets.symmetric(vertical: 0,horizontal:16),
                              child:
                              Column(
                                mainAxisAlignment:MainAxisAlignment.start,
                                crossAxisAlignment:CrossAxisAlignment.start,
                                mainAxisSize:MainAxisSize.max,
                                children: [
                                  Text(
                                    "Shift Step",
                                    textAlign: TextAlign.start,
                                    maxLines:1,
                                    overflow:TextOverflow.clip,
                                    style:TextStyle(
                                      fontWeight:FontWeight.w700,
                                      fontStyle:FontStyle.normal,
                                      fontSize:16,
                                      color:Color(0xff000000),
                                    ),
                                  ),
                                  Padding(
                                    padding:EdgeInsets.fromLTRB(0, 4, 0, 0),
                                    child:Text(
                                      "1000",
                                      textAlign: TextAlign.start,
                                      maxLines:1,
                                      overflow:TextOverflow.ellipsis,
                                      style:TextStyle(
                                        fontWeight:FontWeight.w400,
                                        fontStyle:FontStyle.normal,
                                        fontSize:14,
                                        color:Color(0xff6c6c6c),
                                      ),
                                    ),
                                  ),
                                ],),),),
                          Icon(
                            Icons.arrow_forward_ios,
                            color:Color(0xff212435),
                            size:24,
                          ),
                        ],),),
                  ),

                  Card(
                    margin:EdgeInsets.fromLTRB(0, 0, 0, 16),
                    color:Color(0xffffffff),
                    shadowColor:Color(0x4d939393),
                    elevation:1,
                    shape:RoundedRectangleBorder(
                      borderRadius:BorderRadius.circular(4.0),
                      side: BorderSide(color:Color(0x4d9e9e9e), width:1),
                    ),
                    child:
                    Padding(
                      padding:EdgeInsets.all(16),
                      child:Row(
                        mainAxisAlignment:MainAxisAlignment.start,
                        crossAxisAlignment:CrossAxisAlignment.center,
                        mainAxisSize:MainAxisSize.max,
                        children:[

                          Expanded(
                            flex: 1,
                            child: Padding(
                              padding:EdgeInsets.symmetric(vertical: 0,horizontal:16),
                              child:
                              Column(
                                mainAxisAlignment:MainAxisAlignment.start,
                                crossAxisAlignment:CrossAxisAlignment.start,
                                mainAxisSize:MainAxisSize.max,
                                children: [
                                  Text(
                                    "Shifter Direction",
                                    textAlign: TextAlign.start,
                                    maxLines:1,
                                    overflow:TextOverflow.clip,
                                    style:TextStyle(
                                      fontWeight:FontWeight.w700,
                                      fontStyle:FontStyle.normal,
                                      fontSize:16,
                                      color:Color(0xff000000),
                                    ),
                                  ),
                                  Padding(
                                    padding:EdgeInsets.fromLTRB(0, 4, 0, 0),
                                    child:Text(
                                      "Off",
                                      textAlign: TextAlign.start,
                                      maxLines:1,
                                      overflow:TextOverflow.ellipsis,
                                      style:TextStyle(
                                        fontWeight:FontWeight.w400,
                                        fontStyle:FontStyle.normal,
                                        fontSize:14,
                                        color:Color(0xff6c6c6c),
                                      ),
                                    ),
                                  ),
                                ],),),),
                          Icon(
                            Icons.arrow_forward_ios,
                            color:Color(0xff212435),
                            size:24,
                          ),
                        ],),),
                  ),

                  Card(
                    margin:EdgeInsets.fromLTRB(0, 0, 0, 16),
                    color:Color(0xffffffff),
                    shadowColor:Color(0x4d939393),
                    elevation:1,
                    shape:RoundedRectangleBorder(
                      borderRadius:BorderRadius.circular(4.0),
                      side: BorderSide(color:Color(0x4d9e9e9e), width:1),
                    ),
                    child:
                    Padding(
                      padding:EdgeInsets.all(16),
                      child:Row(
                        mainAxisAlignment:MainAxisAlignment.start,
                        crossAxisAlignment:CrossAxisAlignment.center,
                        mainAxisSize:MainAxisSize.max,
                        children:[

                          Expanded(
                            flex: 1,
                            child: Padding(
                              padding:EdgeInsets.symmetric(vertical: 0,horizontal:16),
                              child:
                              Column(
                                mainAxisAlignment:MainAxisAlignment.start,
                                crossAxisAlignment:CrossAxisAlignment.start,
                                mainAxisSize:MainAxisSize.max,
                                children: [
                                  Text(
                                    "Incline Multiplier",
                                    textAlign: TextAlign.start,
                                    maxLines:1,
                                    overflow:TextOverflow.clip,
                                    style:TextStyle(
                                      fontWeight:FontWeight.w700,
                                      fontStyle:FontStyle.normal,
                                      fontSize:16,
                                      color:Color(0xff000000),
                                    ),
                                  ),
                                  Padding(
                                    padding:EdgeInsets.fromLTRB(0, 4, 0, 0),
                                    child:Text(
                                      "3.0",
                                      textAlign: TextAlign.start,
                                      maxLines:1,
                                      overflow:TextOverflow.ellipsis,
                                      style:TextStyle(
                                        fontWeight:FontWeight.w400,
                                        fontStyle:FontStyle.normal,
                                        fontSize:14,
                                        color:Color(0xff6c6c6c),
                                      ),
                                    ),
                                  ),
                                ],),),),
                          Icon(
                            Icons.arrow_forward_ios,
                            color:Color(0xff212435),
                            size:24,
                          ),
                        ],),),
                  ),
                ],),
            ],),),),
    )
    ;}
}