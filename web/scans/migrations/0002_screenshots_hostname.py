# Generated by Django 4.0.5 on 2022-11-25 06:39

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('scans', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='screenshots',
            name='hostname',
            field=models.CharField(blank=True, max_length=100),
        ),
    ]
