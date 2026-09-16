import 'package:flutter/material.dart';
import 'school_login_screen.dart';

void main() => runApp(const EduPaySchoolApp());

class EduPaySchoolApp extends StatelessWidget {
  const EduPaySchoolApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EduPay School Portal',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff08783e)),
          scaffoldBackgroundColor: const Color(0xfff5f8f6),
        ),
        home: const SchoolLoginScreen(),
      );
}
